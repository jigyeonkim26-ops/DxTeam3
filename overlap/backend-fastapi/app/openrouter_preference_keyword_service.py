"""OpenRouter keyword extraction over read-only Record recommendation DTOs."""

import json
from typing import Any, Callable

import httpx

from .ai_recommendation_errors import AIConfigurationError, AIRequestError, AIResponseError
from .ai_recommendation_models import PreferenceKeywordResponse
from .config import OPENROUTER_API_KEY, OPENROUTER_MODEL
from .recommendation_record_adapter import RecommendationRecord


class OpenRouterPreferenceKeywordService:
    API_URL = "https://openrouter.ai/api/v1/chat/completions"

    def __init__(self, api_key: str | None = None, model: str | None = None,
                 post_json: Callable[..., Any] | None = None) -> None:
        self.api_key = OPENROUTER_API_KEY if api_key is None else api_key.strip()
        self.model = OPENROUTER_MODEL if model is None else model.strip()
        self._post_json = post_json or httpx.post

    def extract_keywords(self, records: list[RecommendationRecord]) -> PreferenceKeywordResponse:
        if not records:
            return PreferenceKeywordResponse()
        if not self.api_key or not self.model:
            raise AIConfigurationError("OpenRouter is not configured")
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": (
                    "Return JSON only: {\"keywords\":[{\"keyword\":string,\"score\":number}]}. "
                    "Extract at most five Korean preferences about place settings, atmosphere, or activities. "
                    "Scores are 0 to 1. Exclude simple emotion words and visited place names. Merge synonyms."
                )},
                {"role": "user", "content": json.dumps([{
                    "content": record.content, "emotion_code": record.emotion_code.value,
                    "emotion_meaning": record.emotion_meaning, "place_name": record.place_name,
                } for record in records], ensure_ascii=False)},
            ],
            "response_format": {"type": "json_object"},
        }
        try:
            response = self._post_json(self.API_URL, headers={
                "Authorization": f"Bearer {self.api_key}", "Content-Type": "application/json",
            }, json=payload, timeout=30.0)
            response.raise_for_status()
            text = response.json()["choices"][0]["message"]["content"]
            start, end = text.find("{"), text.rfind("}")
            parsed = json.loads(text[start:end + 1] if start >= 0 <= end else text)
            response_model = PreferenceKeywordResponse.model_validate(parsed)
        except httpx.HTTPError as exc:
            raise AIRequestError from exc
        except (KeyError, IndexError, TypeError, ValueError) as exc:
            raise AIResponseError from exc
        place_names = {" ".join((record.place_name or "").split()).casefold() for record in records}
        unique = []
        seen = set()
        for item in response_model.keywords:
            key = " ".join(item.keyword.split()).casefold()
            if key and key not in seen and key not in place_names:
                seen.add(key)
                unique.append(item)
        unique.sort(key=lambda item: item.score, reverse=True)
        return PreferenceKeywordResponse(keywords=unique[:5])
