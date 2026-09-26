"""Text model client. Speaks the OpenAI chat-completions protocol, which both
Gemini (OpenAI-compatible endpoint) and most gateways accept."""

import json
import re

import httpx

from .config import settings


class LLMError(RuntimeError):
    pass


def extract_json(text: str) -> dict:
    text = text.strip()
    fence = re.search(r"```(?:json)?\s*(.*?)```", text, re.S)
    if fence:
        text = fence.group(1)
    start, end = text.find("{"), text.rfind("}")
    if start == -1 or end == -1:
        raise LLMError(f"model did not return JSON: {text[:200]}")
    return json.loads(text[start : end + 1])


def chat_json(system: str, user: str, temperature: float = 0.8) -> dict:
    if settings.llm_provider == "fake":
        from .fake_llm import fake_response

        return fake_response(system, user)
    resp = httpx.post(
        settings.llm_base_url.rstrip("/") + "/chat/completions",
        headers={"Authorization": f"Bearer {settings.llm_api_key}"},
        json={
            "model": settings.llm_model,
            "temperature": temperature,
            "response_format": {"type": "json_object"},
            "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
        },
        timeout=120,
    )
    if resp.status_code >= 400:
        raise LLMError(f"LLM HTTP {resp.status_code}: {resp.text[:300]}")
    return extract_json(resp.json()["choices"][0]["message"]["content"])
