"""Rank Tavily/OpenAI place candidates with Gemini while retaining candidate validation."""

import json
from typing import Any, Callable

import httpx

from .config import GEMINI_API_KEY, GEMINI_MODEL
from .models import PlaceCandidate, PlaceCandidateResponse, PlaceRecommendationResponse, PreferenceKeyword, RecommendationMemory
from .place_recommendation_service import (
    PlaceRecommendationService,
    RecommendationRequestError,
    RecommendationServiceNotConfiguredError,
)


class MissingGeminiRecommendationKeyError(RecommendationServiceNotConfiguredError):
    pass


class _StaticResponse:
    def __init__(self, text: str) -> None:
        self.text = text

    def raise_for_status(self) -> None:
        return None

    def json(self) -> dict[str, Any]:
        return {"output": [{"type": "message", "content": [{"type": "output_text", "text": self.text}]}]}


class GeminiPlaceRecommendationService:
    API_URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"

    def __init__(self, api_key: str | None = None, model: str | None = None,
                 post_json: Callable[..., Any] | None = None) -> None:
        self.api_key = GEMINI_API_KEY if api_key is None else api_key.strip()
        self.model = (GEMINI_MODEL if model is None else model).strip()
        self._post_json = post_json or httpx.post

    def recommend(self, memories: list[RecommendationMemory], keywords: list[PreferenceKeyword],
                  candidates: list[PlaceCandidate] | PlaceCandidateResponse) -> PlaceRecommendationResponse:
        candidate_list = candidates.candidates if isinstance(candidates, PlaceCandidateResponse) else candidates
        if not memories or not keywords or not candidate_list:
            return PlaceRecommendationResponse(recommendations=[])
        if not self.api_key or not self.model:
            raise MissingGeminiRecommendationKeyError

        data = {
            "preferences": [{"keyword": item.keyword, "score": item.score} for item in keywords],
            "positive_memories": [{
                "content": memory.content, "emotion_code": memory.emotion_code.value,
                "emotion_meaning": memory.emotion_meaning, "place_name": memory.place_name,
            } for memory in memories],
            "place_candidates": [{
                "name": item.name, "address": item.address, "matched_keywords": item.matched_keywords,
                "summary": item.summary, "source_url": item.source_url,
            } for item in candidate_list],
        }
        instruction = (
            "Return JSON only: {\"recommendations\":[{\"name\":string,\"address\":string|null,"
            "\"source_url\":string,\"match_score\":number,\"matched_keywords\":[string],\"reason\":string}]}. "
            "Rank only provided place_candidates. Never create, rename, substitute, or alter a candidate's "
            "name, address, or source_url. Select at most three distinct candidates, descending by match_score "
            "(0 to 1). Higher preference scores matter proportionally more. matched_keywords may contain only "
            "provided preferences. Write each reason in Korean from the positive memories and preferences; do "
            "not use popularity or search rank. Return an empty array if no candidate fits."
        )
        payload = {
            "systemInstruction": {"parts": [{"text": instruction}]},
            "contents": [{"role": "user", "parts": [{"text": json.dumps(data, ensure_ascii=False)}]}],
            "generationConfig": {"responseMimeType": "application/json"},
        }
        try:
            response = self._post_json(self.API_URL.format(model=self.model), headers={"x-goog-api-key": self.api_key},
                                       json=payload, timeout=45.0)
            response.raise_for_status()
            assessment_text = response.json()["candidates"][0]["content"]["parts"][0]["text"]
        except (httpx.HTTPError, KeyError, IndexError, TypeError, ValueError) as exc:
            raise RecommendationRequestError from exc

        # Delegate post-response validation to the established OpenAI implementation:
        # it rejects candidates/keywords outside the provided lists and preserves source/coordinates.
        validator = PlaceRecommendationService(
            api_key="validation-only",
            post_json=lambda *args, **kwargs: _StaticResponse(assessment_text),
        )
        return validator.recommend(memories, keywords, candidate_list)
