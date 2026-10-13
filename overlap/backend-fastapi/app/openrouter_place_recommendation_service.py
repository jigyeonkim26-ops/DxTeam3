"""OpenRouter ranking constrained to the Tavily candidate list."""

import json
import logging
from typing import Any, Callable

import httpx
from pydantic import ValidationError

from .ai_recommendation_errors import AIConfigurationError, AIRequestError, AIResponseError, InvalidRecommendationError
from .ai_recommendation_models import (
    PlaceCandidate, PlaceCandidateResponse, PlaceRecommendationResponse, PreferenceKeyword, RecommendedPlace,
)
from .config import OPENROUTER_API_KEY, OPENROUTER_MODEL
from .recommendation_record_adapter import RecommendationRecord

logger = logging.getLogger("uvicorn.error")


class OpenRouterPlaceRecommendationService:
    API_URL = "https://openrouter.ai/api/v1/chat/completions"
    _RANKING_SCHEMA = {
        "name": "place_recommendations",
        "strict": True,
        "schema": {
            "type": "object",
            "properties": {
                "recommendations": {
                    "type": "array", "maxItems": 3,
                    "items": {
                        "type": "object",
                        "properties": {
                            "kakao_place_id": {"type": "string", "minLength": 1},
                            "match_score": {"type": "number", "minimum": 0, "maximum": 1},
                            "matched_keywords": {"type": "array", "items": {"type": "string"}},
                            "reason": {"type": "string", "minLength": 1, "maxLength": 500},
                        },
                        "required": ["kakao_place_id", "match_score", "matched_keywords", "reason"],
                        "additionalProperties": False,
                    },
                },
            },
            "required": ["recommendations"],
            "additionalProperties": False,
        },
    }

    def __init__(self, api_key: str | None = None, model: str | None = None,
                 post_json: Callable[..., Any] | None = None) -> None:
        self.api_key = OPENROUTER_API_KEY if api_key is None else api_key.strip()
        self.model = OPENROUTER_MODEL if model is None else model.strip()
        self._post_json = post_json or httpx.post

    @staticmethod
    def _parse_recommendations_content(content: Any) -> list[Any]:
        """Extract a JSON object or array from a model response without trusting prose."""
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
        if isinstance(parsed, dict):
            raw = parsed.get("recommendations", [])
        elif isinstance(parsed, list):
            raw = parsed
        else:
            raise TypeError("OpenRouter JSON must be an object or array")
        if not isinstance(raw, list):
            raise TypeError("recommendations must be an array")
        return raw

    def recommend(self, records: list[RecommendationRecord], keywords: list[PreferenceKeyword],
                  candidates: list[PlaceCandidate] | PlaceCandidateResponse) -> PlaceRecommendationResponse:
        candidate_list = candidates.candidates if isinstance(candidates, PlaceCandidateResponse) else candidates
        if not records or not keywords or not candidate_list:
            return PlaceRecommendationResponse()
        if not self.api_key or not self.model:
            raise AIConfigurationError("OpenRouter is not configured")
        if any(not candidate.kakao_place_id for candidate in candidate_list):
            raise InvalidRecommendationError("candidate has no verified Kakao place ID")
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": (
                    "Return JSON only: {\"recommendations\":[{\"kakao_place_id\":string,"
                    "\"match_score\":number,\"matched_keywords\":[string],\"reason\":string}]}. "
                    "Select at most three distinct Kakao place IDs only from place_candidates. "
                    "Scores are 0 to 1 descending. Higher preference scores matter more. "
                    "matched_keywords must come from preferences. Write concise Korean personalized reasons."
                )},
                {"role": "user", "content": json.dumps({
                    "preferences": [item.model_dump() for item in keywords],
                    "positive_records": [{"content": item.content, "emotion_meaning": item.emotion_meaning,
                                          "place_name": item.place_name} for item in records],
                    "place_candidates": [item.model_dump(exclude={"latitude", "longitude"}) for item in candidate_list],
                }, ensure_ascii=False)},
            ],
            "response_format": {"type": "json_schema", "json_schema": self._RANKING_SCHEMA},
            "provider": {"require_parameters": True},
            "temperature": 0,
            "max_tokens": 900,
            "stream": False,
        }
        try:
            response = self._post_json(self.API_URL, headers={
                "Authorization": f"Bearer {self.api_key}", "Content-Type": "application/json",
            }, json=payload, timeout=45.0)
            response.raise_for_status()
            text = response.json()["choices"][0]["message"]["content"]
            raw = self._parse_recommendations_content(text)
        except httpx.HTTPError as exc:
            raise AIRequestError from exc
        except (KeyError, IndexError, TypeError, ValueError) as exc:
            raise AIResponseError from exc
        logger.info("AI recommendation diagnostic ranking_output_count=%d", len(raw))
        candidate_index = {item.kakao_place_id: item for item in candidate_list}
        preference_names = {" ".join(item.keyword.split()).casefold(): item.keyword for item in keywords}
        ranked = []
        for item in raw:
            try:
                candidate = candidate_index.get(str(item["kakao_place_id"]))
                if candidate is None:
                    raise InvalidRecommendationError("candidate is not in the supplied list")
                matches = []
                for keyword in item["matched_keywords"]:
                    canonical = preference_names.get(" ".join(keyword.split()).casefold())
                    if canonical is None:
                        raise InvalidRecommendationError("unknown preference keyword")
                    if canonical not in matches:
                        matches.append(canonical)
                ranked.append((float(item["match_score"]), candidate, matches, item["reason"]))
            except (KeyError, TypeError, ValueError) as exc:
                raise AIResponseError from exc
        logger.info("AI recommendation diagnostic validated_recommendations_count=%d", len(ranked))
        ranked.sort(key=lambda item: item[0], reverse=True)
        output, seen = [], set()
        for score, candidate, matches, reason in ranked:
            identity = candidate.kakao_place_id
            if identity in seen:
                continue
            seen.add(identity)
            try:
                output.append(RecommendedPlace(rank=len(output) + 1, kakao_place_id=candidate.kakao_place_id,
                                               name=candidate.name, address=candidate.address,
                                               latitude=candidate.latitude, longitude=candidate.longitude,
                                               match_score=score, matched_keywords=matches, reason=reason,
                                               source_url=candidate.source_url))
            except ValidationError as exc:
                raise AIResponseError("Invalid recommendation fields") from exc
            if len(output) == 3:
                break
        logger.info("AI recommendation diagnostic final_response_count=%d", len(output))
        return PlaceRecommendationResponse(recommendations=output)
