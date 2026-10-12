"""OpenRouter keyword extraction over read-only Record recommendation DTOs."""

import json
import logging
import re
from collections import Counter
from typing import Any, Callable

import httpx

from .ai_recommendation_errors import AIConfigurationError, AIRequestError, AIResponseError
from .ai_recommendation_models import PreferenceKeywordResponse
from .config import OPENROUTER_API_KEY, OPENROUTER_MODEL
from .recommendation_record_adapter import RecommendationRecord

logger = logging.getLogger("uvicorn.error")


class OpenRouterPreferenceKeywordService:
    API_URL = "https://openrouter.ai/api/v1/chat/completions"
    _STOP_TOKENS = frozenset({"좋아요", "좋았어요", "최고", "괜찮아요", "괜찮았어요", "별로", "실망"})
    _KEYWORD_SCHEMA = {
        "name": "place_preference_keywords",
        "strict": True,
        "schema": {
            "type": "object",
            "properties": {
                "keywords": {
                    "type": "array", "maxItems": 5,
                    "items": {
                        "type": "object",
                        "properties": {
                            "keyword": {"type": "string", "minLength": 1, "maxLength": 40},
                            "score": {"type": "number", "minimum": 0, "maximum": 1},
                        },
                        "required": ["keyword", "score"],
                        "additionalProperties": False,
                    },
                },
            },
            "required": ["keywords"],
            "additionalProperties": False,
        },
    }

    def __init__(self, api_key: str | None = None, model: str | None = None,
                 post_json: Callable[..., Any] | None = None) -> None:
        self.api_key = OPENROUTER_API_KEY if api_key is None else api_key.strip()
        self.model = OPENROUTER_MODEL if model is None else model.strip()
        self._post_json = post_json or httpx.post

    @staticmethod
    def _parse_keywords_content(content: Any) -> dict[str, Any]:
        """Extract the expected keyword JSON from a model response without trusting prose."""
        if not isinstance(content, str):
            raise TypeError("OpenRouter content must be a string")
        text = content.strip()
        if text.startswith("```"):
            line_end = text.find("\n")
            if line_end < 0:
                logger.info("AI recommendation diagnostic invalid_structure_category=unterminated_fence")
                raise ValueError("unterminated markdown fence")
            text = text[line_end + 1:]
            fence_end = text.rfind("```")
            if fence_end >= 0:
                text = text[:fence_end]
            text = text.strip()

        starts = [index for index in (text.find("{"), text.find("[")) if index >= 0]
        if not starts:
            logger.info("AI recommendation diagnostic invalid_structure_category=missing_json")
            raise ValueError("OpenRouter content does not contain JSON")
        try:
            parsed, _ = json.JSONDecoder().raw_decode(text[min(starts):])
        except json.JSONDecodeError:
            logger.info("AI recommendation diagnostic invalid_structure_category=invalid_json")
            raise
        if isinstance(parsed, list):
            return {"keywords": parsed}
        if not isinstance(parsed, dict) or "keywords" not in parsed:
            raise TypeError("OpenRouter JSON must contain keywords")
        if not isinstance(parsed["keywords"], list):
            raise TypeError("keywords must be an array")
        return parsed

    @classmethod
    def _fallback_keywords(cls, records: list[RecommendationRecord]) -> PreferenceKeywordResponse:
        """Derive frequency-only fallback keywords from the existing positive-record input."""
        place_tokens = {
            token.casefold()
            for record in records
            for token in re.findall(r"[가-힣A-Za-z0-9]{2,}", record.place_name or "")
        }
        frequencies: Counter[str] = Counter()
        for record in records:
            for token in re.findall(r"[가-힣A-Za-z0-9]{2,}", record.content):
                normalized = token.casefold()
                if normalized not in place_tokens and normalized not in cls._STOP_TOKENS:
                    frequencies[normalized] += 1
        if not frequencies:
            return PreferenceKeywordResponse()
        maximum = max(frequencies.values())
        keywords = [
            {"keyword": token, "score": count / maximum}
            for token, count in sorted(frequencies.items(), key=lambda item: (-item[1], item[0]))[:5]
        ]
        return PreferenceKeywordResponse.model_validate({"keywords": keywords})

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
            "response_format": {"type": "json_schema", "json_schema": self._KEYWORD_SCHEMA},
            "provider": {"require_parameters": True},
            "temperature": 0,
            "max_tokens": 300,
            "stream": False,
        }
        try:
            response = self._post_json(self.API_URL, headers={
                "Authorization": f"Bearer {self.api_key}", "Content-Type": "application/json",
            }, json=payload, timeout=30.0)
            response.raise_for_status()
            text = response.json()["choices"][0]["message"]["content"]
            parsed = self._parse_keywords_content(text)
            response_model = PreferenceKeywordResponse.model_validate(parsed)
        except httpx.HTTPError as exc:
            fallback = self._fallback_keywords(records)
            logger.info("AI recommendation diagnostic keyword_fallback_count=%d", len(fallback.keywords))
            return fallback
        except (KeyError, IndexError, TypeError, ValueError) as exc:
            fallback = self._fallback_keywords(records)
            logger.info("AI recommendation diagnostic keyword_fallback_count=%d", len(fallback.keywords))
            return fallback
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
