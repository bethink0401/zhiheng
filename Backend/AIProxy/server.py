#!/usr/bin/env python3
"""Local development proxy for Zhiheng's real DeepSeek Responses API calls.

The proxy binds to loopback by default. It keeps DEEPSEEK_API_KEY out of the
iPhone app and forwards only the already-aggregated HealthFactPack.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from collections.abc import Iterator
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, BinaryIO


DEEPSEEK_RESPONSES_URL = "https://api.deepseek.com/responses"
DEFAULT_MODEL = "deepseek-v4-flash"
MAX_REQUEST_BYTES = 256 * 1024
ALLOWED_METRICS = [
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
]
ALLOWED_PLAN_IDS = [
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
]


def response_schema() -> dict[str, Any]:
    return {
        "type": "object",
        "additionalProperties": False,
        "required": [
            "summary",
            "supportiveClosing",
            "observedFacts",
            "possibleFactors",
            "uncertainty",
            "followUpQuestion",
            "suggestedAction",
            "safetyLevel",
            "usedMetrics",
        ],
        "properties": {
            "summary": {"type": "string"},
            "supportiveClosing": {
                "type": "string",
                "minLength": 1,
                "maxLength": 160,
            },
            "observedFacts": {
                "type": "array",
                "maxItems": 6,
                "items": {"type": "string"},
            },
            "possibleFactors": {
                "type": "array",
                "maxItems": 5,
                "items": {"type": "string"},
            },
            "uncertainty": {"type": "string"},
            "followUpQuestion": {
                "anyOf": [{"type": "string"}, {"type": "null"}]
            },
            "suggestedAction": {
                "anyOf": [
                    {
                        "type": "object",
                        "additionalProperties": False,
                        "required": ["templateID", "rationale"],
                        "properties": {
                            "templateID": {
                                "type": "string",
                                "enum": ALLOWED_PLAN_IDS,
                            },
                            "rationale": {"type": "string"},
                        },
                    },
                    {"type": "null"},
                ]
            },
            "safetyLevel": {
                "type": "string",
                "enum": ["normal", "caution", "urgent"],
            },
            "usedMetrics": {
                "type": "array",
                "items": {"type": "string", "enum": ALLOWED_METRICS},
            },
        },
    }


def validate_client_request(payload: Any) -> dict[str, Any]:
    if not isinstance(payload, dict):
        raise ValueError("request must be a JSON object")
    question = payload.get("question")
    fact_pack = payload.get("factPack")
    conversation = payload.get("recentConversation", [])
    if not isinstance(question, str) or not question.strip() or len(question) > 2000:
        raise ValueError("question is missing or too long")
    if not isinstance(fact_pack, dict):
        raise ValueError("factPack is missing")
    if not isinstance(conversation, list) or len(conversation) > 10:
        raise ValueError("recentConversation is invalid")
    return {
        "question": question.strip(),
        "factPack": fact_pack,
        "recentConversation": conversation,
    }


def build_deepseek_request(
    client_payload: dict[str, Any],
    *,
    stream: bool = False,
) -> dict[str, Any]:
    model = os.environ.get("DEEPSEEK_MODEL", DEFAULT_MODEL)
    instructions = (
        "你是知衡的健康解释助手，像一位真正记得上下文、愿意认真听用户说话的健康伙伴那样对话。"
        "不要用客服、报告或固定话术。先用一句自然的话接住用户真正关心的事，再直接回答；"
        "根据问题变化措辞，不要重复‘从数据来看’‘根据记录’‘建议你’等开场。结合 recentConversation 延续上下文。"
        "用户即使没有可用健康数据，也可以获得一般健康教育；这时必须明确没有使用其个人记录。"
        "只能把输入中的结构化健康事实包作为用户个人数据来源，不能编造数值、症状、事件、"
        "趋势或因果关系。用户询问个人状态时先判断数据质量，并综合所有与问题相关且可用的指标，"
        "不要只挑一个指标下结论。observedFacts 通常列出三至六条最相关事实；不足三类可用数据时"
        "列出全部相关事实，不得为了凑数重复或编造。usedMetrics 必须覆盖回答和 observedFacts"
        "实际引用的每一类可用指标。summary 使用自然连贯的中文直接作答，通常二至四个短段落；"
        "第一句必须说清最重要的回答，并用 Markdown **加粗第一句中的核心短语**。不要使用机械标题、"
        "固定开场或字段清单，除非用户要求，否则避免编号列表。需要特别注意的变化、数据不足、"
        "安全停止条件或就医提示也使用 Markdown **加粗**，整篇只加粗一至三个关键短语。"
        "supportiveClosing 必须填写一至两句自然中文，具体回应这位用户当前的问题、努力或可完成的"
        "小行动，给出真诚但不过度的鼓励。不能重复 summary，不能使用‘加油’‘保持积极’"
        "‘一切都会好起来’等空泛口号，不能虚构情绪、症状或结果，也不能作健康保证。"
        "把事实和可能因素保留在各自结构字段中，最多提出一个真正有助于理解问题的追问；"
        "追问是让用户回答的问题，不是建议用户再次向 AI 提问。不得诊断疾病、"
        "推荐处方药、停药或调整剂量，也不得承诺持续监护。建议行动最多选择一个"
        "允许的低风险微计划模板，并说明它为什么适合当前事实；没有充分依据时 suggestedAction 必须为 null。"
        "不得自行计算变化幅度或趋势；事实包没有趋势字段时，不得声称指标上升或下降。"
        "current.value 是最近一次本地汇总，不是平均值；baseline.medianValue 是基线中位数，"
        "需要清楚说明比较依据和局限。possibleFactors 只能表达可能性，不得写成因果；"
        "如有必要，只提出一个追问。usedMetrics 只能列出回答实际使用且"
        "事实包中可用的指标。必须输出 JSON；uncertainty 必须是单个字符串，不能是数组。"
        "输出示例：{\"summary\":\"直接、自然的完整回答\",\"supportiveClosing\":\"具体而自然的鼓励\",\"observedFacts\":[],"
        "\"possibleFactors\":[],\"uncertainty\":\"数据限制\","
        "\"followUpQuestion\":null,\"suggestedAction\":null,"
        "\"safetyLevel\":\"normal\",\"usedMetrics\":[]}。使用简洁自然的中文。"
    )
    return {
        "model": model,
        "store": False,
        "stream": stream,
        "max_output_tokens": 1200,
        "reasoning": {"effort": "none"},
        "temperature": 0.45,
        "instructions": instructions,
        "input": json.dumps(client_payload, ensure_ascii=False, separators=(",", ":")),
        "text": {
            "format": {
                "type": "json_schema",
                "name": "zhiheng_health_ai_response",
                "schema": response_schema(),
            }
        },
    }


def extract_structured_response(provider_payload: dict[str, Any]) -> dict[str, Any]:
    for item in provider_payload.get("output", []):
        if item.get("type") != "message":
            continue
        for content in item.get("content", []):
            if content.get("type") == "output_text" and isinstance(content.get("text"), str):
                result = json.loads(content["text"])
                if isinstance(result, dict):
                    return result
    raise ValueError("DeepSeek response did not contain structured output text")


def normalize_structured_response(
    payload: dict[str, Any],
    _client_payload: dict[str, Any],
) -> dict[str, Any]:
    """Make DeepSeek's JSON decodable without judging or rewriting its content."""
    required_keys = {
        "summary",
        "observedFacts",
        "possibleFactors",
        "uncertainty",
        "followUpQuestion",
        "suggestedAction",
        "safetyLevel",
        "usedMetrics",
    }
    compatibility_keys = {"supportiveClosing"}
    if not required_keys.issubset(payload) or not set(payload).issubset(
        required_keys | compatibility_keys
    ):
        raise ValueError("model response keys do not match the approved schema")

    uncertainty = payload["uncertainty"]
    if isinstance(uncertainty, list) and all(
        isinstance(item, str) for item in uncertainty
    ):
        uncertainty = "；".join(uncertainty)

    if not isinstance(payload["summary"], str):
        raise ValueError("summary is invalid")
    supportive_closing = payload.get("supportiveClosing")
    if supportive_closing is not None and not isinstance(supportive_closing, str):
        raise ValueError("supportiveClosing is invalid")
    for key, limit in (("observedFacts", 6), ("possibleFactors", 5)):
        value = payload[key]
        if not isinstance(value, list) or len(value) > limit or not all(
            isinstance(item, str) for item in value
        ):
            raise ValueError(f"{key} is invalid")
    if not isinstance(uncertainty, str):
        raise ValueError("uncertainty is invalid")
    if payload["followUpQuestion"] is not None and not isinstance(
        payload["followUpQuestion"], str
    ):
        raise ValueError("followUpQuestion is invalid")
    if payload["safetyLevel"] not in {"normal", "caution", "urgent"}:
        raise ValueError("safetyLevel is invalid")

    action = payload["suggestedAction"]
    if action is not None and (
        not isinstance(action, dict)
        or set(action) != {"templateID", "rationale"}
        or action.get("templateID") not in ALLOWED_PLAN_IDS
        or not isinstance(action.get("rationale"), str)
    ):
        raise ValueError("suggestedAction is invalid")

    used_metrics = payload["usedMetrics"]
    if (
        not isinstance(used_metrics, list)
        or not all(metric in ALLOWED_METRICS for metric in used_metrics)
    ):
        raise ValueError("usedMetrics is invalid")

    normalized = dict(payload)
    normalized["uncertainty"] = uncertainty
    return normalized


def call_deepseek(client_payload: dict[str, Any]) -> dict[str, Any]:
    api_key = os.environ.get("DEEPSEEK_API_KEY") or os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("DEEPSEEK_API_KEY is not configured in the proxy environment")
    body = json.dumps(build_deepseek_request(client_payload)).encode("utf-8")
    request = urllib.request.Request(
        DEEPSEEK_RESPONSES_URL,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        extracted = extract_structured_response(json.load(response))
        return normalize_structured_response(extracted, client_payload)


def open_deepseek_stream(client_payload: dict[str, Any]) -> BinaryIO:
    api_key = os.environ.get("DEEPSEEK_API_KEY") or os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise RuntimeError("DEEPSEEK_API_KEY is not configured in the proxy environment")
    body = json.dumps(
        build_deepseek_request(client_payload, stream=True)
    ).encode("utf-8")
    request = urllib.request.Request(
        DEEPSEEK_RESPONSES_URL,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "Accept": "text/event-stream",
        },
    )
    return urllib.request.urlopen(request, timeout=60)


def iter_deepseek_sse_events(response: BinaryIO) -> Iterator[dict[str, Any]]:
    """Yield semantic event payloads while ignoring framing and keep-alives."""
    for raw_line in response:
        line = raw_line.decode("utf-8").strip()
        if not line or line.startswith(":") or not line.startswith("data:"):
            continue
        payload = json.loads(line[5:].strip())
        if isinstance(payload, dict):
            yield payload


class ZhihengAIProxyHandler(BaseHTTPRequestHandler):
    server_version = "ZhihengAIProxy/0.2"

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/healthz":
            self._send_json(200, {
                "status": "ok",
                "provider": "deepseek",
                "model": os.environ.get("DEEPSEEK_MODEL", DEFAULT_MODEL),
                "adapterVersion": 3,
            })
            return
        self._send_json(404, {"error": "not_found"})

    def do_POST(self) -> None:  # noqa: N802
        if self.path != "/v1/health-assistant/respond":
            self._send_json(404, {"error": "not_found"})
            return
        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            if content_length <= 0 or content_length > MAX_REQUEST_BYTES:
                raise ValueError("request body size is invalid")
            payload = json.loads(self.rfile.read(content_length))
            validated = validate_client_request(payload)
            if "text/event-stream" in self.headers.get("Accept", ""):
                self._stream_deepseek(validated)
            else:
                result = call_deepseek(validated)
                self._send_json(200, result)
        except (ValueError, json.JSONDecodeError) as error:
            self._send_json(400, {"error": "invalid_request", "message": str(error)})
        except RuntimeError as error:
            self._send_json(503, {"error": "proxy_not_configured", "message": str(error)})
        except urllib.error.HTTPError as error:
            self._send_json(error.code, {"error": "model_service_rejected"})
        except (urllib.error.URLError, TimeoutError):
            self._send_json(503, {"error": "model_service_unavailable"})
        except Exception:
            self._send_json(500, {"error": "internal_error"})

    def log_message(self, format: str, *args: Any) -> None:
        # Never log request bodies, questions, fact packs, or authorization data.
        sys.stderr.write("AIProxy %s - %s\n" % (self.address_string(), format % args))

    def _send_json(self, status: int, payload: dict[str, Any]) -> None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _stream_deepseek(self, client_payload: dict[str, Any]) -> None:
        with open_deepseek_stream(client_payload) as provider_response:
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream; charset=utf-8")
            self.send_header("Cache-Control", "no-cache")
            self.end_headers()

            structured_fragments: list[str] = []
            try:
                for event in iter_deepseek_sse_events(provider_response):
                    event_type = event.get("type")
                    if event_type == "response.output_text.delta":
                        delta = event.get("delta")
                        if isinstance(delta, str):
                            structured_fragments.append(delta)
                            self._write_sse(event_type, {"delta": delta})
                    elif event_type == "response.completed":
                        structured = json.loads("".join(structured_fragments))
                        if not isinstance(structured, dict):
                            raise ValueError("streamed response is not an object")
                        normalized = normalize_structured_response(
                            structured,
                            client_payload,
                        )
                        self._write_sse(event_type, {"response": normalized})
                        return
                    elif event_type in {"response.incomplete", "response.failed"}:
                        self._write_sse("response.failed", {})
                        return
                self._write_sse("response.failed", {})
            except (ValueError, json.JSONDecodeError, UnicodeDecodeError):
                self._write_sse("response.failed", {})
            except (BrokenPipeError, ConnectionResetError):
                return

    def _write_sse(self, event_type: str, payload: dict[str, Any]) -> None:
        body = {"type": event_type, **payload}
        encoded = json.dumps(body, ensure_ascii=False, separators=(",", ":"))
        self.wfile.write(f"event: {event_type}\n".encode("utf-8"))
        self.wfile.write(f"data: {encoded}\n\n".encode("utf-8"))
        self.wfile.flush()


def main() -> None:
    host = os.environ.get("ZHIHENG_PROXY_HOST", "127.0.0.1")
    port = int(os.environ.get("ZHIHENG_PROXY_PORT", "8787"))
    server = ThreadingHTTPServer((host, port), ZhihengAIProxyHandler)
    print(f"Zhiheng AI proxy listening on http://{host}:{port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
