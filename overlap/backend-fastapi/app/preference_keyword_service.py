"""Extract preference keywords from positive memory data via structured LLM output."""

import json
from typing import Any, Callable

import httpx
from pydantic import ValidationError

from .config import OPENAI_API_KEY
from .models import PreferenceKeywordResponse, RecommendationMemory


class PreferenceAnalysisError(Exception):
    """Base error for preference analysis failures."""


class MissingOpenAIKeyError(PreferenceAnalysisError):
    pass


class PreferenceLLMRequestError(PreferenceAnalysisError):
    pass


class InvalidPreferenceResponseError(PreferenceAnalysisError):
    pass


class PreferenceKeywordService:
    API_URL = "https://api.openai.com/v1/chat/completions"
    DEFAULT_MODEL = "gpt-4o-mini"

    def __init__(
        self,
        api_key: str | None = None,
        model: str = DEFAULT_MODEL,
        post_json: Callable[..., Any] | None = None,
    ) -> None:
        self.api_key = OPENAI_API_KEY if api_key is None else api_key.strip()
        self.model = model
        self._post_json = post_json or httpx.post

    def extract_keywords(
        self, memories: list[RecommendationMemory]
    ) -> PreferenceKeywordResponse:
        if not memories:
            return PreferenceKeywordResponse(keywords=[])
        if not self.api_key:
            raise MissingOpenAIKeyError

        # Only preference signals are sent. IDs, addresses, coordinates, and dates
        # are unnecessary for this extraction step and stay on the application side.
        records = [
            {
                "content": memory.content,
                "emotion_code": memory.emotion_code.value,
                "emotion_meaning": memory.emotion_meaning,
                "place_name": memory.place_name,
            }
            for memory in memories
        ]
        schema = {
            "type": "object",
            "properties": {
                "keywords": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "keyword": {"type": "string"},
                            "score": {"type": "number"},
                        },
                        "required": ["keyword", "score"],
                        "additionalProperties": False,
                    },
                }
            },
            "required": ["keywords"],
            "additionalProperties": False,
        }
        payload = {
            "model": self.model,
            "messages": [
                {
                    "role": "system",
                    "content": (
                        "Extract the user's recurring preferences about place settings, "
                        "activities, and atmosphere from the positive memory records. "
                        "Return only preference keywords, never recommend or invent a "
                        "place. Prefer concrete concepts such as sunset, night views, "
                        "walking, quiet places, nature, cafes, sea, views, secluded "
                        "places, photography, or dates. Exclude generic sentiment words "
                        "such as good, best, happy, or fun. Normalize synonymous phrases "
                        "to one concise Korean keyword (for example, 조용함/조용한 곳 "
                        "to 조용한; 산책하기 좋음/산책 to 산책). Return at most five "
                        "distinct keywords, strongest preference first. Score each from "
                        "0 to 1 based on recurrence across records and strength of the "
                        "positive emotion. If no place preference is supported, return "
                        "an empty keywords array."
                    ),
                },
                {
                    "role": "user",
                    "content": json.dumps(records, ensure_ascii=False),
                },
            ],
            "response_format": {
                "type": "json_schema",
                "json_schema": {
                    "name": "preference_keyword_response",
                    "strict": True,
                    "schema": schema,
                },
            },
        }

        try:
            response = self._post_json(
                self.API_URL,
                headers={"Authorization": f"Bearer {self.api_key}"},
                json=payload,
                timeout=30.0,
            )
            response.raise_for_status()
        except httpx.HTTPError as exc:
            raise PreferenceLLMRequestError from exc

        try:
            envelope = response.json()
            content = envelope["choices"][0]["message"]["content"]
            parsed = json.loads(content)
            raw_keywords = parsed["keywords"]
            if not isinstance(raw_keywords, list):
                raise TypeError("keywords must be an array")
        except (json.JSONDecodeError, KeyError, IndexError, TypeError, ValueError) as exc:
            raise InvalidPreferenceResponseError from exc

        try:
            # Cap before model validation, then remove exact normalized duplicates.
            unique = []
            seen: set[str] = set()
            for item in raw_keywords:
                if not isinstance(item, dict) or not isinstance(item.get("keyword"), str):
                    unique.append(item)
                    continue
                normalized = " ".join(item["keyword"].split()).casefold()
                if normalized and normalized not in seen:
                    seen.add(normalized)
                    unique.append(item)
            result = PreferenceKeywordResponse.model_validate(
                {"keywords": unique[:5]}
            )
            result.keywords.sort(key=lambda item: item.score, reverse=True)
            return result
        except ValidationError as exc:
            raise InvalidPreferenceResponseError from exc
