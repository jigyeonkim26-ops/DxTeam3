"""Turn web search hints into real, region-matched Kakao points of interest."""

import math
import re
from collections import Counter
from typing import Callable

import httpx

from .ai_recommendation_errors import AIConfigurationError, AIRequestError, AIResponseError
from .ai_recommendation_models import PlaceCandidate, PlaceCandidateResponse, PreferenceKeyword
from .config import KAKAO_REST_API_KEY
from .kakao import search_places
from .recommendation_record_adapter import RecommendationRecord


class KakaoPlaceVerificationService:
    # Four web hints and, when needed, direct searches. Each Kakao call
    # has its own six-second timeout; a recommendation never fans out freely.
    MAX_CALLS = 6
    MAX_WEB_HINTS = 4

    def __init__(self, search: Callable[[str], list[dict]] | None = None) -> None:
        self._requires_key = search is None
        self._search = search or (lambda query: search_places(query, timeout=6.0))

    @staticmethod
    def _name(value: str | None) -> str:
        return re.sub(r"[^\w]", "", value or "").casefold()

    @staticmethod
    def _region(records: list[RecommendationRecord]) -> str | None:
        regions = [record.address.split()[0] for record in records if record.address and record.address.split()]
        return Counter(regions).most_common(1)[0][0] if regions else None

    @staticmethod
    def _valid_place(place: dict, region: str) -> bool:
        try:
            address = place["address"]
            latitude, longitude = float(place["latitude"]), float(place["longitude"])
            return (
                isinstance(place["kakao_place_id"], str)
                and bool(re.fullmatch(r"\d+", place["kakao_place_id"]))
                and isinstance(place["name"], str) and bool(place["name"].strip())
                and isinstance(address, str) and bool(address.strip())
                and address.split()[0] == region
                and -90 <= latitude <= 90 and -180 <= longitude <= 180
                and math.isfinite(latitude) and math.isfinite(longitude)
                and isinstance(place["place_url"], str) and bool(place["place_url"].strip())
            )
        except (KeyError, TypeError, ValueError, IndexError):
            return False

    def verify(
        self, hints: PlaceCandidateResponse, keywords: list[PreferenceKeyword],
        records: list[RecommendationRecord],
    ) -> PlaceCandidateResponse:
        region = self._region(records)
        if not region or not keywords:
            return PlaceCandidateResponse()
        if self._requires_key and not KAKAO_REST_API_KEY:
            raise AIConfigurationError("Kakao is not configured")
        visited_ids = {record.kakao_place_id for record in records if record.kakao_place_id}
        visited_names = {self._name(record.place_name) for record in records if record.place_name}
        verified: list[PlaceCandidate] = []
        seen_ids: set[str] = set()
        calls = 0

        def lookup(query: str) -> list[dict]:
            nonlocal calls
            if calls >= self.MAX_CALLS:
                return []
            calls += 1
            try:
                results = self._search(query)
                if not isinstance(results, list):
                    raise AIResponseError("Invalid Kakao search response")
                return results
            except httpx.HTTPError as exc:
                raise AIRequestError("Kakao place search failed") from exc
            except (KeyError, TypeError, ValueError) as exc:
                raise AIResponseError("Invalid Kakao search response") from exc

        def add(place: dict, *, hint: PlaceCandidate | None = None, keyword: str | None = None) -> None:
            if not isinstance(place, dict) or not self._valid_place(place, region):
                return
            place_id = str(place["kakao_place_id"]).strip()
            if place_id in visited_ids or place_id in seen_ids:
                return
            name = self._name(place["name"])
            if name in visited_names:
                return
            if hint is not None and name != self._name(hint.name):
                return
            seen_ids.add(place_id)
            verified.append(PlaceCandidate(
                kakao_place_id=place_id, name=place["name"], address=place["address"],
                latitude=float(place["latitude"]), longitude=float(place["longitude"]),
                matched_keywords=(hint.matched_keywords if hint is not None else [keyword] if keyword else []),
                summary=(hint.summary if hint is not None else f"{region}의 카카오 장소 검색에서 확인된 장소"),
                source_url=place["place_url"],
            ))

        for hint in hints.candidates[:self.MAX_WEB_HINTS]:
            if len(verified) >= 10 or calls >= self.MAX_CALLS:
                break
            for place in lookup(f"{region} {hint.name}"):
                add(place, hint=hint)
                if len(verified) >= 10:
                    break

        if len(verified) < 3:
            for item in sorted(keywords, key=lambda value: value.score, reverse=True)[:3]:
                if len(verified) >= 10 or calls >= self.MAX_CALLS:
                    break
                for place in lookup(f"{region} {item.keyword}"):
                    add(place, keyword=item.keyword)
                    if len(verified) >= 10:
                        break
        return PlaceCandidateResponse(candidates=verified)
