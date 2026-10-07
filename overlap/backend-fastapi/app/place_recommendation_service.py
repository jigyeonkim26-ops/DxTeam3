"""Rank web-search place candidates against a user's positive preferences."""

import json
from typing import Annotated, Any, Callable

import httpx
from pydantic import BaseModel, Field, StringConstraints, ValidationError
from .config import OPENAI_API_KEY
from .models import (
    PlaceCandidate,
    PlaceCandidateResponse,
    PlaceRecommendationResponse,
    PreferenceKeyword,
    RecommendationMemory,
    RecommendedPlace,
)


class PlaceRecommendationError(Exception):
    """Base error for final recommendation generation."""


class RecommendationServiceNotConfiguredError(PlaceRecommendationError):
    pass


class RecommendationRequestError(PlaceRecommendationError):
    pass


class RecommendationResponseParseError(PlaceRecommendationError):
    pass


class InvalidRecommendationError(PlaceRecommendationError):
    pass


class _RecommendationAssessment(BaseModel):
    name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=160)]
    address: str | None = None
    source_url: str
    match_score: float = Field(ge=0, le=1, allow_inf_nan=False)
    matched_keywords: list[str]
    reason: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=500)]


class _RecommendationAssessmentResponse(BaseModel):
    recommendations: list[_RecommendationAssessment]


class PlaceRecommendationService:
    API_URL = "https://api.openai.com/v1/responses"
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

    @staticmethod
    def _normalize(value: str | None) -> str:
        return " ".join((value or "").split()).casefold()

    def recommend(
        self,
        memories: list[RecommendationMemory],
        keywords: list[PreferenceKeyword],
        candidates: list[PlaceCandidate] | PlaceCandidateResponse,
    ) -> PlaceRecommendationResponse:
        if not memories or not keywords:
            return PlaceRecommendationResponse(recommendations=[])
        candidate_list = candidates.candidates if isinstance(candidates, PlaceCandidateResponse) else candidates
        if not candidate_list:
            return PlaceRecommendationResponse(recommendations=[])
        if not self.api_key:
            raise RecommendationServiceNotConfiguredError

        preference_terms = {self._normalize(item.keyword): item for item in keywords}
        # Keep only the fields needed for matching. User and memory identifiers,
        # precise past coordinates, and visit timestamps are never sent to the LLM.
        input_data = {
            "preferences": [
                {"keyword": item.keyword, "score": item.score} for item in keywords
            ],
            "positive_memories": [
                {
                    "content": memory.content,
                    "emotion_code": memory.emotion_code.value,
                    "emotion_meaning": memory.emotion_meaning,
                    "place_name": memory.place_name,
                }
                for memory in memories
            ],
            "place_candidates": [
                {
                    "name": candidate.name,
                    "address": candidate.address,
                    "matched_keywords": candidate.matched_keywords,
                    "summary": candidate.summary,
                    "source_url": candidate.source_url,
                }
                for candidate in candidate_list
            ],
        }
        schema = {
            "type": "object",
            "properties": {
                "recommendations": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "name": {"type": "string"},
                            "address": {"type": ["string", "null"]},
                            "source_url": {"type": "string"},
                            "match_score": {"type": "number"},
                            "matched_keywords": {
                                "type": "array",
                                "items": {"type": "string"},
                            },
                            "reason": {"type": "string"},
                        },
                        "required": [
                            "name",
                            "address",
                            "source_url",
                            "match_score",
                            "matched_keywords",
                            "reason",
                        ],
                        "additionalProperties": False,
                    },
                }
            },
            "required": ["recommendations"],
            "additionalProperties": False,
        }
        payload = {
            "model": self.model,
            "instructions": (
                "Rank only the provided place candidates for this user's preferences. "
                "Do not create, rename, or substitute a place. Match each candidate "
                "against every preference and its 0-to-1 score; higher-scored "
                "preferences must contribute proportionally more to the overall "
                "match_score. The match_score is overall personal fit from 0 to 1, "
                "not popularity or search order. Use the positive memories as evidence "
                "for the user's tastes. Write a brief personalized reason in Korean, "
                "grounded in those preferences or memories. Summarize preference traits; "
                "do not quote the original comment at length. Exclude generic reasons "
                "such as popularity or simply calling a place good. Return only "
                "provided preference keywords in matched_keywords. Copy the candidate's "
                "name, address, and source_url exactly. Do not produce coordinates. "
                "Return at most three distinct best-fit candidates, sorted by match_score "
                "descending. If none has a supported personal fit, return an empty list."
            ),
            "input": json.dumps(input_data, ensure_ascii=False),
            "text": {
                "format": {
                    "type": "json_schema",
                    "name": "place_recommendation_assessment",
                    "strict": True,
                    "schema": schema,
                }
            },
        }

        try:
            response = self._post_json(
                self.API_URL,
                headers={"Authorization": f"Bearer {self.api_key}"},
                json=payload,
                timeout=45.0,
            )
            response.raise_for_status()
        except httpx.HTTPError as exc:
            raise RecommendationRequestError from exc

        try:
            envelope = response.json()
            text = "\n".join(
                content["text"]
                for item in envelope["output"]
                if item.get("type") == "message"
                for content in item.get("content", [])
                if content.get("type") == "output_text"
            )
            parsed = json.loads(text)
            assessment_response = _RecommendationAssessmentResponse.model_validate(parsed)
        except (ValueError, TypeError, KeyError, IndexError, AttributeError, ValidationError) as exc:
            raise RecommendationResponseParseError from exc

        candidate_index: dict[tuple[str, str, str], PlaceCandidate] = {}
        for candidate in candidate_list:
            key = (
                self._normalize(candidate.name),
                self._normalize(candidate.address),
                candidate.source_url,
            )
            candidate_index[key] = candidate

        ranked: list[tuple[_RecommendationAssessment, PlaceCandidate, list[str]]] = []
        for assessment in assessment_response.recommendations:
            key = (
                self._normalize(assessment.name),
                self._normalize(assessment.address),
                assessment.source_url,
            )
            candidate = candidate_index.get(key)
            if candidate is None:
                raise InvalidRecommendationError("Recommendation is not in the candidate list")

            canonical_matches: list[str] = []
            seen_keywords: set[str] = set()
            for keyword in assessment.matched_keywords:
                normalized = self._normalize(keyword)
                preference = preference_terms.get(normalized)
                if preference is None:
                    raise InvalidRecommendationError("Recommendation contains an unknown preference keyword")
                if normalized not in seen_keywords:
                    seen_keywords.add(normalized)
                    canonical_matches.append(preference.keyword)
            if canonical_matches:
                ranked.append((assessment, candidate, canonical_matches))

        ranked.sort(key=lambda item: item[0].match_score, reverse=True)
        recommendations: list[RecommendedPlace] = []
        seen_places: set[tuple[str, str]] = set()
        for assessment, candidate, matched_keywords in ranked:
            identity = (
                self._normalize(candidate.name),
                self._normalize(candidate.address),
            )
            if identity in seen_places:
                continue
            seen_places.add(identity)
            recommendations.append(
                RecommendedPlace(
                    rank=len(recommendations) + 1,
                    name=candidate.name,
                    address=candidate.address,
                    latitude=candidate.latitude,
                    longitude=candidate.longitude,
                    match_score=assessment.match_score,
                    matched_keywords=matched_keywords,
                    reason=assessment.reason,
                    source_url=candidate.source_url,
                )
            )
            if len(recommendations) == 3:
                break

        return PlaceRecommendationResponse(recommendations=recommendations)
