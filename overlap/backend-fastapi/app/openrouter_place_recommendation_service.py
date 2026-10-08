"""Rank supplied place candidates through OpenRouter without trusting model identity fields."""

import json
from typing import Any, Callable

import httpx

from .config import OPENROUTER_API_KEY, OPENROUTER_MODEL
from .gemini_place_recommendation_service import _StaticResponse
from .models import PlaceCandidate, PlaceCandidateResponse, PlaceRecommendationResponse, PreferenceKeyword, RecommendationMemory
from .place_recommendation_service import (
    PlaceRecommendationService,
    RecommendationRequestError,
    RecommendationServiceNotConfiguredError,
)


class MissingOpenRouterRecommendationKeyError(RecommendationServiceNotConfiguredError):
    pass


class OpenRouterPlaceRecommendationService:
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

    def recommend(self, memories: list[RecommendationMemory], keywords: list[PreferenceKeyword],
                  candidates: list[PlaceCandidate] | PlaceCandidateResponse) -> PlaceRecommendationResponse:
        candidate_list = candidates.candidates if isinstance(candidates, PlaceCandidateResponse) else candidates
        if not memories or not keywords or not candidate_list:
            return PlaceRecommendationResponse(recommendations=[])
        if not self.api_key or not self.model:
            raise MissingOpenRouterRecommendationKeyError
        data = {
            "preferences": [{"keyword": item.keyword, "score": item.score} for item in keywords],
            "positive_memories": [{
                "content": memory.content, "emotion_meaning": memory.emotion_meaning,
                "place_name": memory.place_name,
            } for memory in memories],
            "place_candidates": [{
                "name": item.name, "address": item.address, "matched_keywords": item.matched_keywords,
                "summary": item.summary, "source_url": item.source_url,
            } for item in candidate_list],
        }
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": (
                    "Return JSON only: {\"recommendations\":[{\"name\":string,\"address\":string|null,"
                    "\"source_url\":string,\"match_score\":number,\"matched_keywords\":[string],\"reason\":string}]}. "
                    "Choose at most three distinct candidates only from place_candidates. Never create, rename, "
                    "substitute, or alter names, addresses, or source URLs. Higher preference scores count more. "
                    "Sort by match_score descending from 0 to 1. matched_keywords must use only preferences. "
                    "Write concise Korean personalized reasons based on preferences and positive memories."
                )},
                {"role": "user", "content": json.dumps(data, ensure_ascii=False)},
            ],
            "response_format": {"type": "json_object"},
        }
        try:
            response = self._post_json(
                self.API_URL,
                headers={"Authorization": f"Bearer {self.api_key}", "Content-Type": "application/json"},
                json=payload, timeout=45.0,
            )
            response.raise_for_status()
            assessment_text = self._json_text(response.json()["choices"][0]["message"]["content"])
        except (httpx.HTTPError, KeyError, IndexError, TypeError, ValueError) as exc:
            raise RecommendationRequestError from exc
        validator = PlaceRecommendationService(
            api_key="validation-only",
            post_json=lambda *args, **kwargs: _StaticResponse(assessment_text),
        )
        return validator.recommend(memories, keywords, candidate_list)
