import json
import io
import os
import unittest
from unittest.mock import patch

import server


class AIProxyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.payload = {
            "question": "我最近睡得怎么样？",
            "factPack": {
                "dataMode": "demo",
                "metrics": [],
                "unavailableMetrics": [],
            },
            "recentConversation": [],
        }

    def test_request_uses_responses_api_structured_output_without_storage(self) -> None:
        self.payload["factPack"]["metrics"] = [{
            "metric": "sleepDuration",
            "baseline": {"medianValue": 7.4},
        }]
        with patch.dict(os.environ, {"DEEPSEEK_MODEL": "test-model"}, clear=False):
            request = server.build_deepseek_request(self.payload)

        self.assertEqual(request["model"], "test-model")
        self.assertFalse(request["store"])
        self.assertEqual(request["reasoning"], {"effort": "none"})
        self.assertEqual(request["temperature"], 0.45)
        self.assertEqual(request["text"]["format"]["type"], "json_schema")
        self.assertIn(
            "supportiveClosing",
            request["text"]["format"]["schema"]["required"],
        )
        self.assertNotIn("DEEPSEEK_API_KEY", json.dumps(request))
        self.assertIn("baseline", json.loads(request["input"])["factPack"]["metrics"][0])

    def test_stream_request_enables_responses_sse(self) -> None:
        request = server.build_deepseek_request(self.payload, stream=True)

        self.assertTrue(request["stream"])
        self.assertEqual(request["text"]["format"]["type"], "json_schema")

    def test_sse_parser_ignores_framing_and_keep_alive(self) -> None:
        source = io.BytesIO(
            b": keep-alive\n"
            b"event: response.output_text.delta\n"
            b'data: {"type":"response.output_text.delta","delta":"{\\\"summary\\\":"}\n'
            b"\n"
            b'event: response.completed\n'
            b'data: {"type":"response.completed"}\n\n'
        )

        events = list(server.iter_deepseek_sse_events(source))

        self.assertEqual(len(events), 2)
        self.assertEqual(events[0]["type"], "response.output_text.delta")
        self.assertEqual(events[1]["type"], "response.completed")

    def test_schema_accepts_all_sixteen_supported_health_metrics(self) -> None:
        expected = {
            "stepCount",
            "sleepDuration",
            "restingHeartRate",
            "heartRateVariability",
            "activeEnergy",
            "exerciseDuration",
            "standHours",
            "heartRate",
            "respiratoryRate",
            "oxygenSaturation",
            "wristTemperature",
            "walkingRunningDistance",
            "flightsClimbed",
            "walkingSpeed",
            "walkingStepLength",
            "vo2Max",
        }

        self.assertEqual(set(server.ALLOWED_METRICS), expected)
        metric_schema = server.response_schema()["properties"]["usedMetrics"]
        self.assertEqual(set(metric_schema["items"]["enum"]), expected)

    def test_schema_accepts_all_ten_supported_micro_plans(self) -> None:
        expected = {
            "afternoonCaffeineCutoff",
            "earlierBedtime",
            "afternoonWalk",
            "movementBreak",
            "reducedTrainingLoad",
            "bedtimeBreathing",
            "morningDaylight",
            "afterMealWalk",
            "consistentWakeTime",
            "gentleMobility",
        }

        self.assertEqual(set(server.ALLOWED_PLAN_IDS), expected)
        action_schema = server.response_schema()["properties"]["suggestedAction"]
        plan_schema = action_schema["anyOf"][0]["properties"]["templateID"]
        self.assertEqual(set(plan_schema["enum"]), expected)

    def test_client_request_rejects_missing_fact_pack(self) -> None:
        with self.assertRaises(ValueError):
            server.validate_client_request({"question": "hello"})

    def test_client_request_accepts_ten_context_turns_but_rejects_eleven(self) -> None:
        self.payload["recentConversation"] = [
            {"role": "user", "content": f"turn-{index}"}
            for index in range(10)
        ]
        validated = server.validate_client_request(self.payload)
        self.assertEqual(len(validated["recentConversation"]), 10)

        self.payload["recentConversation"].append(
            {"role": "assistant", "content": "turn-10"}
        )
        with self.assertRaises(ValueError):
            server.validate_client_request(self.payload)

    def test_extracts_structured_output(self) -> None:
        expected = {"summary": "ok"}
        payload = {
            "output": [
                {
                    "type": "message",
                    "content": [
                        {"type": "output_text", "text": json.dumps(expected)}
                    ],
                }
            ]
        }
        self.assertEqual(server.extract_structured_response(payload), expected)

    def test_normalizes_uncertainty_array_for_json_field_compatibility(self) -> None:
        self.payload["factPack"]["metrics"] = [{"metric": "sleepDuration"}]
        response = {
            "summary": "仅陈述可用事实",
            "observedFacts": ["最近一次睡眠汇总为 7.4 小时"],
            "possibleFactors": [],
            "uncertainty": ["没有睡眠质量信息", "不能判断趋势"],
            "followUpQuestion": None,
            "suggestedAction": None,
            "safetyLevel": "normal",
            "usedMetrics": ["sleepDuration"],
        }

        normalized = server.normalize_structured_response(response, self.payload)

        self.assertEqual(
            normalized["uncertainty"],
            "没有睡眠质量信息；不能判断趋势",
        )

    def test_does_not_block_schema_compatible_model_content(self) -> None:
        response = {
            "summary": "摘要",
            "observedFacts": [],
            "possibleFactors": [],
            "uncertainty": "数据有限",
            "followUpQuestion": None,
            "suggestedAction": None,
            "safetyLevel": "normal",
            "usedMetrics": ["sleepDuration"],
        }

        normalized = server.normalize_structured_response(response, self.payload)

        self.assertEqual(normalized, response)

    def test_preserves_provider_interpretation_without_rewriting_it(self) -> None:
        self.payload["factPack"]["metrics"] = [{"metric": "sleepDuration"}]
        response = {
            "summary": "睡眠时长处于稳定水平",
            "observedFacts": [],
            "possibleFactors": ["可能与规律作息有关"],
            "uncertainty": "数据有限",
            "followUpQuestion": None,
            "suggestedAction": None,
            "safetyLevel": "normal",
            "usedMetrics": ["sleepDuration"],
        }

        normalized = server.normalize_structured_response(response, self.payload)

        self.assertEqual(normalized["summary"], response["summary"])
        self.assertEqual(normalized["possibleFactors"], response["possibleFactors"])

    def test_preserves_structured_supportive_closing(self) -> None:
        response = {
            "summary": "**今晚先把休息守住。**",
            "supportiveClosing": "不用一次做到完美，先完成今晚这一小步就很好。",
            "observedFacts": [],
            "possibleFactors": [],
            "uncertainty": "数据有限",
            "followUpQuestion": None,
            "suggestedAction": None,
            "safetyLevel": "normal",
            "usedMetrics": [],
        }

        normalized = server.normalize_structured_response(response, self.payload)

        self.assertEqual(normalized, response)


if __name__ == "__main__":
    unittest.main()
