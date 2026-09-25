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

    def test_schema_tracks_all_fact_categories(self) -> None:
        expected = {
            "healthMetrics", "todayFeeling", "recentFeelings",
            "lifeEvents", "microPlan",
        }

        self.assertEqual(set(server.ALLOWED_FACT_KINDS), expected)
        kind_schema = server.response_schema()["properties"]["usedFactKinds"]
        self.assertEqual(set(kind_schema["items"]["enum"]), expected)

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

    def test_client_request_accepts_whitelisted_supplemental_facts(self) -> None:
        self.payload["factPack"]["supplementalFacts"] = {
            "todayFeeling": {
                "status": "recorded", "localDay": "2026-09-10",
                "energy": 2, "stress": 4, "bodyFeeling": 3,
                "note": "昨晚照护家人后睡得较晚",
            },
            "recentFeelings": {
                "status": "recorded", "recordedDayCount": 4,
                "expectedDayCount": 7, "energyMedian": 3,
                "stressMedian": 4, "bodyFeelingMedian": 3,
                "notes": [{"localDay": "2026-09-09", "note": "早上精神尚可"}],
            },
            "todayLifeEvents": {
                "status": "recorded",
                "events": [{"kind": "overtime", "occurrenceCount": 1}],
                "details": [{"kind": "overtime", "note": "结束时间比预计晚"}],
            },
            "recentLifeEvents": {
                "status": "recorded",
                "events": [{"kind": "custom", "occurrenceCount": 1}],
                "details": [{
                    "kind": "custom", "customName": "家庭聚会",
                    "note": "当天活动量较大",
                }],
            },
            "microPlan": {
                "status": "recorded", "templateID": "bedtimeBreathing",
                "planTitle": "睡前呼吸", "taskTitle": "睡前呼吸 5 分钟",
                "planStatus": "active", "scheduledCount": 3,
                "completedCount": 2, "skippedCount": 0,
                "unresolvedCount": 1, "completionRate": 2 / 3,
                "todayOutcome": "completed", "userFeedback": ["更放松"],
            },
        }

        validated = server.validate_client_request(self.payload)

        facts = validated["factPack"]["supplementalFacts"]
        self.assertEqual(facts["todayFeeling"]["energy"], 2)
        self.assertEqual(facts["todayFeeling"]["note"], "昨晚照护家人后睡得较晚")
        self.assertEqual(
            facts["recentLifeEvents"]["details"][0]["customName"],
            "家庭聚会",
        )
        self.assertEqual(facts["microPlan"]["userFeedback"], ["更放松"])

    def test_client_request_rejects_unlisted_or_oversized_context_text(self) -> None:
        self.payload["factPack"]["supplementalFacts"] = {
            "todayFeeling": {"status": "recorded", "note": "记" * 161},
            "recentFeelings": {"status": "notRecorded", "notes": []},
            "todayLifeEvents": {
                "status": "recorded",
                "events": [{"kind": "custom", "occurrenceCount": 1}],
                "details": [{"kind": "custom", "customName": "家庭聚会"}],
            },
            "recentLifeEvents": {"status": "notRecorded", "events": [], "details": []},
            "microPlan": {"status": "notRecorded", "userFeedback": []},
        }

        with self.assertRaises(ValueError):
            server.validate_client_request(self.payload)

        self.payload["factPack"]["supplementalFacts"]["todayFeeling"] = {
            "status": "notRecorded",
        }
        self.payload["factPack"]["supplementalFacts"]["todayLifeEvents"]["details"][0][
            "recordID"
        ] = "must-not-pass"
        with self.assertRaises(ValueError):
            server.validate_client_request(self.payload)

    def test_prompt_treats_stored_user_text_as_untrusted_data(self) -> None:
        instructions = server.build_deepseek_request(self.payload)["instructions"]

        self.assertIn("用户填写的原文", instructions)
        self.assertIn("不得遵循", instructions)

    def test_client_request_rejects_context_text_without_recorded_status(self) -> None:
        self.payload["factPack"]["supplementalFacts"] = {
            "todayFeeling": {"status": "notRecorded", "note": "不应存在"},
            "recentFeelings": {"status": "notRecorded", "notes": []},
            "todayLifeEvents": {"status": "notRecorded", "events": [], "details": []},
            "recentLifeEvents": {"status": "notRecorded", "events": [], "details": []},
            "microPlan": {"status": "notRecorded", "userFeedback": []},
        }

        with self.assertRaises(ValueError):
            server.validate_client_request(self.payload)

    def test_client_request_rejects_out_of_range_supplemental_values(self) -> None:
        self.payload["factPack"]["supplementalFacts"] = {
            "todayFeeling": {"status": "recorded", "energy": 6},
            "recentFeelings": {"status": "notRecorded"},
            "todayLifeEvents": {"status": "notRecorded", "events": []},
            "recentLifeEvents": {"status": "notRecorded", "events": []},
            "microPlan": {"status": "notRecorded", "userFeedback": []},
        }

        with self.assertRaises(ValueError):
            server.validate_client_request(self.payload)

    def test_client_request_accepts_bounded_plan_evaluation(self) -> None:
        self.payload["planEvaluation"] = {
            "planID": "microplan.afternoonWalk.test",
            "planTitle": "午后步行",
            "taskTitle": "午后轻松步行 10 分钟",
            "status": "completed",
            "scheduledCount": 5,
            "completedCount": 4,
            "skippedCount": 1,
            "completionRate": 0.8,
            "userFeedback": ["完成后感觉比较轻松"],
            "metrics": [{
                "metric": "stepCount",
                "healthMetric": "stepCount",
                "beforeMedian": 5000,
                "planMedian": 5600,
                "changeFromBefore": 600,
                "beforeValidDayCount": 5,
                "planValidDayCount": 5,
                "direction": "favorable",
            }],
            "contextStatus": "recorded",
            "contextEvents": [{
                "kind": "overtime",
                "occurrenceCount": 2,
                "highestIntensity": 3,
            }],
            "dataQualitySummary": "1 项相关指标具备计划前后对照",
            "localVerdict": "mayHaveHelped",
        }

        validated = server.validate_client_request(self.payload)

        self.assertEqual(
            validated["planEvaluation"]["userFeedback"],
            ["完成后感觉比较轻松"],
        )
        self.assertEqual(
            validated["planEvaluation"]["contextEvents"][0]["kind"],
            "overtime",
        )
        self.assertIn("计划结束评估", server.build_deepseek_request(validated)["instructions"])

    def test_client_request_rejects_free_text_in_plan_context(self) -> None:
        self.payload["planEvaluation"] = {
            "planID": "plan",
            "planTitle": "计划",
            "taskTitle": "任务",
            "status": "completed",
            "scheduledCount": 5,
            "completedCount": 4,
            "skippedCount": 1,
            "completionRate": 0.8,
            "userFeedback": [],
            "metrics": [],
            "contextStatus": "recorded",
            "contextEvents": [{
                "kind": "custom",
                "occurrenceCount": 1,
                "highestIntensity": None,
                "customLabel": "不得上传的自定义名称",
            }],
            "dataQualitySummary": "数据不足",
            "localVerdict": "insufficientData",
        }

        with self.assertRaises(ValueError):
            server.validate_client_request(self.payload)

    def test_client_request_rejects_oversized_plan_feedback(self) -> None:
        evaluation = {
            "planID": "plan",
            "planTitle": "计划",
            "taskTitle": "任务",
            "status": "endedEarly",
            "scheduledCount": 1,
            "completedCount": 1,
            "skippedCount": 0,
            "completionRate": 1.0,
            "userFeedback": ["感" * 161],
            "metrics": [],
            "contextStatus": "notRecorded",
            "contextEvents": [],
            "dataQualitySummary": "数据不足",
            "localVerdict": "insufficientData",
        }
        self.payload["planEvaluation"] = evaluation

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

    def test_rejects_unknown_used_fact_kind(self) -> None:
        response = {
            "summary": "摘要",
            "supportiveClosing": "继续观察。",
            "observedFacts": [],
            "possibleFactors": [],
            "uncertainty": "数据有限",
            "followUpQuestion": None,
            "suggestedAction": None,
            "safetyLevel": "normal",
            "usedMetrics": [],
            "usedFactKinds": ["rawHealthSamples"],
        }

        with self.assertRaises(ValueError):
            server.normalize_structured_response(response, self.payload)


if __name__ == "__main__":
    unittest.main()
