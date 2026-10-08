"""Extract place-preference keywords with Gemini's REST API."""

import json
from typing import Any, Callable

import httpx
from pydantic import ValidationError

from .config import GEMINI_API_KEY, GEMINI_MODEL
from .models import PreferenceKeywordResponse, RecommendationMemory
from .preference_keyword_service import (
    InvalidPreferenceResponseError,
    MissingOpenAIKeyError,
    PreferenceLLMRequestError,
)


class MissingGeminiKeyError(MissingOpenAIKeyError):
    """Raised when the selected Gemini provider has no API key."""


class GeminiPreferenceKeywordService:
    API_URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"

    def __init__(self, api_key: str | None = None, model: str | None = None,
                 post_json: Callable[..., Any] | None = None) -> None:
        self.api_key = GEMINI_API_KEY if api_key is None else api_key.strip()
        self.model = (GEMINI_MODEL if model is None else model).strip()
        self._post_json = post_json or httpx.post

    def extract_keywords(self, memories: list[RecommendationMemory]) -> PreferenceKeywordResponse:
        if not memories:
            return PreferenceKeywordResponse(keywords=[])
        if not self.api_key or not self.model:
            raise MissingGeminiKeyError

        records = [{
            "content": memory.content,
            "emotion_code": memory.emotion_code.value,
            "emotion_meaning": memory.emotion_meaning,
            "place_name": memory.place_name,
        } for memory in memories]
        instruction = (
            "Extract recurring user preferences about places, environments, atmosphere, "
            "and activities from positive memory records. Return JSON only in the given "
            "schema. Return at most five distinct concise Korean keywords with scores from "
            "0 to 1. Prefer concrete concepts such as sunset, quietness, walking, nature, "
            "views, cafes, sea, photography, or dates. Exclude simple emotion words. "
            "Merge synonymous concepts into one keyword. Do not recommend or invent places."
        )
        payload = {
            "systemInstruction": {"parts": [{"text": instruction}]},
            "contents": [{"role": "user", "parts": [{"text": json.dumps(records, ensure_ascii=False)}]}],
            "generationConfig": {"responseMimeType": "application/json"},
        }
        try:
            response = self._post_json(
                self.API_URL.format(model=self.model),
                headers={"x-goog-api-key": self.api_key}, json=payload, timeout=30.0,
            )
            response.raise_for_status()
        except httpx.HTTPError as exc:
            raise PreferenceLLMRequestError from exc
        try:
            envelope = response.json()
            content = envelope["candidates"][0]["content"]["parts"][0]["text"]
            raw_keywords = json.loads(content)["keywords"]
            if not isinstance(raw_keywords, list):
                raise TypeError("keywords must be an array")
            unique: list[dict[str, Any]] = []
            seen: set[str] = set()
            for item in raw_keywords:
                if not isinstance(item, dict) or not isinstance(item.get("keyword"), str):
                    unique.append(item)
                    continue
                normalized = " ".join(item["keyword"].split()).casefold()
                if normalized and normalized not in seen:
                    seen.add(normalized)
                    unique.append(item)
            result = PreferenceKeywordResponse.model_validate({"keywords": unique[:5]})
            result.keywords.sort(key=lambda item: item.score, reverse=True)
            return result
        except (json.JSONDecodeError, KeyError, IndexError, TypeError, ValueError, ValidationError) as exc:
            raise InvalidPreferenceResponseError from exc
