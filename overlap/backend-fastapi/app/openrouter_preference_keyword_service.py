"""Extract place preferences through OpenRouter's OpenAI-compatible API."""

import json
from typing import Any, Callable

import httpx
from pydantic import ValidationError

from .config import OPENROUTER_API_KEY, OPENROUTER_MODEL
from .models import PreferenceKeywordResponse, RecommendationMemory
from .preference_keyword_service import (
    InvalidPreferenceResponseError,
    MissingOpenAIKeyError,
    PreferenceLLMRequestError,
)


class MissingOpenRouterKeyError(MissingOpenAIKeyError):
    pass


class OpenRouterPreferenceKeywordService:
    API_URL = "https://openrouter.ai/api/v1/chat/completions"

    def __init__(self, api_key: str | None = None, model: str | None = None,
                 post_json: Callable[..., Any] | None = None) -> None:
        self.api_key = OPENROUTER_API_KEY if api_key is None else api_key.strip()
        self.model = OPENROUTER_MODEL if model is None else model.strip()
        self._post_json = post_json or httpx.post

    @staticmethod
    def _json_text(value: str) -> str:
        value = value.strip()
        if value.startswith("```"):
            value = value.split("\n", 1)[1] if "\n" in value else ""
            if value.rstrip().endswith("```"):
                value = value.rstrip()[:-3]
        start, end = value.find("{"), value.rfind("}")
        return value[start:end + 1] if start >= 0 and end >= start else value

    def extract_keywords(self, memories: list[RecommendationMemory]) -> PreferenceKeywordResponse:
        if not memories:
            return PreferenceKeywordResponse(keywords=[])
        if not self.api_key or not self.model:
            raise MissingOpenRouterKeyError
        records = [{
            "content": memory.content,
            "emotion_code": memory.emotion_code.value,
            "emotion_meaning": memory.emotion_meaning,
            "place_name": memory.place_name,
        } for memory in memories]
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": (
                    "Return JSON only: {\"keywords\":[{\"keyword\":string,\"score\":number}]}. "
                    "Extract at most five recurring Korean preferences about place settings, atmosphere, "
                    "or activities from positive records. Scores must be from 0 to 1. Exclude simple "
                    "emotion words and the visited place name itself. Merge synonymous concepts. Do not "
                    "recommend or invent places."
                )},
                {"role": "user", "content": json.dumps(records, ensure_ascii=False)},
            ],
            "response_format": {"type": "json_object"},
        }
        try:
            response = self._post_json(
                self.API_URL,
                headers={"Authorization": f"Bearer {self.api_key}", "Content-Type": "application/json"},
                json=payload, timeout=30.0,
            )
            response.raise_for_status()
        except httpx.HTTPError as exc:
            raise PreferenceLLMRequestError from exc
        try:
            content = self._json_text(response.json()["choices"][0]["message"]["content"])
            raw_keywords = json.loads(content)["keywords"]
            if not isinstance(raw_keywords, list):
                raise TypeError("keywords must be an array")
            unique: list[dict[str, Any]] = []
            seen: set[str] = set()
            place_names = {" ".join(memory.place_name.split()).casefold() for memory in memories}
            for item in raw_keywords:
                if not isinstance(item, dict) or not isinstance(item.get("keyword"), str):
                    unique.append(item)
                    continue
                normalized = " ".join(item["keyword"].split()).casefold()
                if normalized and normalized not in seen and normalized not in place_names:
                    seen.add(normalized)
                    unique.append(item)
            result = PreferenceKeywordResponse.model_validate({"keywords": unique[:5]})
            result.keywords.sort(key=lambda item: item.score, reverse=True)
            return result
        except (json.JSONDecodeError, KeyError, IndexError, TypeError, ValueError, ValidationError) as exc:
            raise InvalidPreferenceResponseError from exc
