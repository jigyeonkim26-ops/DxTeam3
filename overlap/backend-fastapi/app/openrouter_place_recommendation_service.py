"""OpenRouter ranking constrained to the Tavily candidate list."""

import json
from typing import Any, Callable

import httpx

from .ai_recommendation_errors import AIConfigurationError, AIRequestError, AIResponseError, InvalidRecommendationError
from .ai_recommendation_models import (
    PlaceCandidate, PlaceCandidateResponse, PlaceRecommendationResponse, PreferenceKeyword, RecommendedPlace,
)
from .config import OPENROUTER_API_KEY, OPENROUTER_MODEL
from .recommendation_record_adapter import RecommendationRecord


class OpenRouterPlaceRecommendationService:
    API_URL = "https://openrouter.ai/api/v1/chat/completions"

    def __init__(self, api_key: str | None = None, model: str | None = None,
                 post_json: Callable[..., Any] | None = None) -> None:
        self.api_key = OPENROUTER_API_KEY if api_key is None else api_key.strip()
        self.model = OPENROUTER_MODEL if model is None else model.strip()
        self._post_json = post_json or httpx.post

    @staticmethod
    def _key(name: str | None, address: str | None, url: str) -> tuple[str, str, str]:
        return (" ".join((name or "").split()).casefold(), " ".join((address or "").split()).casefold(), url)

    def recommend(self, records: list[RecommendationRecord], keywords: list[PreferenceKeyword],
                  candidates: list[PlaceCandidate] | PlaceCandidateResponse) -> PlaceRecommendationResponse:
        candidate_list = candidates.candidates if isinstance(candidates, PlaceCandidateResponse) else candidates
        if not records or not keywords or not candidate_list:
            return PlaceRecommendationResponse()
        if not self.api_key or not self.model:
            raise AIConfigurationError("OpenRouter is not configured")
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": (
                    "Return JSON only: {\"recommendations\":[{\"name\":string,\"address\":string|null,"
                    "\"source_url\":string,\"match_score\":number,\"matched_keywords\":[string],\"reason\":string}]}. "
                    "Select at most three distinct places only from place_candidates. Never alter candidate name, "
                    "address, or source_url. Scores are 0 to 1 descending. Higher preference scores matter more. "
                    "matched_keywords must come from preferences. Write concise Korean personalized reasons."
                )},
                {"role": "user", "content": json.dumps({
                    "preferences": [item.model_dump() for item in keywords],
                    "positive_records": [{"content": item.content, "emotion_meaning": item.emotion_meaning,
                                          "place_name": item.place_name} for item in records],
                    "place_candidates": [item.model_dump(exclude={"latitude", "longitude"}) for item in candidate_list],
                }, ensure_ascii=False)},
            ],
            "response_format": {"type": "json_object"},
        }
        try:
            response = self._post_json(self.API_URL, headers={
                "Authorization": f"Bearer {self.api_key}", "Content-Type": "application/json",
            }, json=payload, timeout=45.0)
            response.raise_for_status()
            text = response.json()["choices"][0]["message"]["content"]
            start, end = text.find("{"), text.rfind("}")
            raw = json.loads(text[start:end + 1] if start >= 0 <= end else text).get("recommendations", [])
            if not isinstance(raw, list):
                raise TypeError("recommendations must be an array")
        except httpx.HTTPError as exc:
            raise AIRequestError from exc
        except (KeyError, IndexError, TypeError, ValueError) as exc:
            raise AIResponseError from exc
        candidate_index = {self._key(item.name, item.address, item.source_url): item for item in candidate_list}
        preference_names = {" ".join(item.keyword.split()).casefold(): item.keyword for item in keywords}
        ranked = []
        for item in raw:
            try:
                key = self._key(item["name"], item.get("address"), item["source_url"])
                candidate = candidate_index.get(key)
                if candidate is None:
                    raise InvalidRecommendationError("candidate is not in the supplied list")
                matches = []
                for keyword in item["matched_keywords"]:
                    canonical = preference_names.get(" ".join(keyword.split()).casefold())
                    if canonical is None:
                        raise InvalidRecommendationError("unknown preference keyword")
                    if canonical not in matches:
                        matches.append(canonical)
                if matches:
                    ranked.append((float(item["match_score"]), candidate, matches, item["reason"]))
            except (KeyError, TypeError, ValueError) as exc:
                raise AIResponseError from exc
        ranked.sort(key=lambda item: item[0], reverse=True)
        output, seen = [], set()
        for score, candidate, matches, reason in ranked:
            identity = (candidate.name.casefold(), (candidate.address or "").casefold())
            if identity in seen:
                continue
            seen.add(identity)
            output.append(RecommendedPlace(rank=len(output) + 1, name=candidate.name, address=candidate.address,
                                            latitude=candidate.latitude, longitude=candidate.longitude,
                                            match_score=score, matched_keywords=matches, reason=reason,
                                            source_url=candidate.source_url))
            if len(output) == 3:
                break
        return PlaceRecommendationResponse(recommendations=output)
