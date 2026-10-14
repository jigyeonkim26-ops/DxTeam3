"""Verify Tavily place hints and bounded preference searches with Kakao Local."""

import logging
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

logger = logging.getLogger("uvicorn.error")

_REGION_CANONICAL = {
    "서울": "서울", "서울시": "서울", "서울특별시": "서울",
    "부산": "부산", "부산시": "부산", "부산광역시": "부산",
    "대구": "대구", "대구시": "대구", "대구광역시": "대구",
    "인천": "인천", "인천시": "인천", "인천광역시": "인천",
    "광주": "광주", "광주광역시": "광주",
    "대전": "대전", "대전광역시": "대전",
    "울산": "울산", "울산광역시": "울산",
    "세종": "세종", "세종시": "세종", "세종특별자치시": "세종",
    "경기": "경기", "경기도": "경기",
    "강원": "강원", "강원도": "강원", "강원특별자치도": "강원",
    "충북": "충북", "충청북도": "충북",
    "충남": "충남", "충청남도": "충남",
    "전북": "전북", "전라북도": "전북", "전북특별자치도": "전북",
    "전남": "전남", "전라남도": "전남",
    "경북": "경북", "경상북도": "경북",
    "경남": "경남", "경상남도": "경남",
    "제주": "제주", "제주도": "제주", "제주특별자치도": "제주",
}


class KakaoPlaceVerificationService:
    # Keep a strict total ceiling, but reserve most calls for concise, grounded
    # preference/place-type searches instead of repeating long web titles.
    MAX_CALLS = 6
    MAX_WEB_HINTS = 2
    MAX_FALLBACK_KEYWORDS = 4

    _QUERY_EXPANSIONS = (
        (("노을", "석양", "일몰", "해질녘", "해넘이", "낙조"), ("일몰 명소", "전망대", "공원", "강변")),
        (("산책", "걷기", "둘레길", "트레킹"), ("산책로", "공원", "수변공원", "호수공원")),
        (("전망", "조망", "뷰"), ("전망대", "전망 공원", "뷰 명소")),
        (("조용", "한적", "차분"), ("조용한 카페", "한적한 공원")),
        (("카페", "커피"), ("분위기 좋은 카페", "뷰 카페")),
        (("자연", "숲", "녹지", "정원"), ("수목원", "자연공원", "산책로")),
    )

    def __init__(self, search: Callable[[str], list[dict]] | None = None) -> None:
        self._requires_key = search is None
        self._search = search or (lambda query: search_places(query, timeout=6.0))

    @staticmethod
    def _name(value: str | None) -> str:
        return re.sub(r"[^\w]", "", value or "").casefold()

    @staticmethod
    def _region_key(value: str | None) -> str:
        token = (value or "").strip().split(maxsplit=1)
        if not token:
            return ""
        first = token[0]
        return _REGION_CANONICAL.get(first, first)

    @classmethod
    def _region(cls, records: list[RecommendationRecord]) -> str | None:
        regions = [
            record.address.split()[0]
            for record in records
            if record.address and record.address.split()
        ]
        return Counter(regions).most_common(1)[0][0] if regions else None

    @classmethod
    def _local_name(cls, value: str | None, region: str) -> str:
        """Drop an explicit leading locality only; retain branch/store suffixes."""
        name = (value or "").strip()
        aliases = [
            alias for alias, canonical in _REGION_CANONICAL.items()
            if canonical == cls._region_key(region)
        ]
        for alias in sorted(aliases, key=len, reverse=True):
            if name.startswith(alias) and len(name) > len(alias) and name[len(alias)].isspace():
                name = name[len(alias):].lstrip()
                break
        return cls._name(name)

    @classmethod
    def _clean_hint_name(cls, value: str, region: str) -> str:
        """Reduce a Tavily title to its POI phrase without changing POI identity."""
        name = re.sub(r"\([^)]*\)|\[[^]]*\]", " ", value or "")
        name = re.split(r"\s[|｜–—]\s|\s-\s", name, maxsplit=1)[0]
        name = re.sub(r"\s+", " ", name).strip(" ,·|-")
        region_key = cls._region_key(region)
        aliases = [alias for alias, canonical in _REGION_CANONICAL.items() if canonical == region_key]
        for alias in sorted(aliases, key=len, reverse=True):
            if name.startswith(alias) and len(name) > len(alias) and name[len(alias)].isspace():
                name = name[len(alias):].lstrip()
                break
        return name

    @classmethod
    def _preference_queries(cls, keywords: list[PreferenceKeyword]) -> list[str]:
        ordered = sorted(keywords, key=lambda value: value.score, reverse=True)
        queries = []
        seen = set()
        for item in ordered:
            raw = item.keyword.strip()
            variants = [raw]
            normalized = re.sub(r"\s+", "", raw).casefold()
            for terms, expansions in cls._QUERY_EXPANSIONS:
                if any(term.casefold() in normalized for term in terms):
                    variants.extend(expansions)
            for variant in variants:
                key = re.sub(r"[^\w]", "", variant).casefold()
                if key and key not in seen:
                    queries.append(variant)
                    seen.add(key)
        return queries

    @classmethod
    def _place_rejection_reason(cls, place: object, region: str) -> str | None:
        if not isinstance(place, dict):
            return "invalid_place_fields"
        place_id = place.get("kakao_place_id")
        if not isinstance(place_id, str) or not re.fullmatch(r"\d+", place_id.strip()):
            return "invalid_place_id"
        name, address, url = place.get("name"), place.get("address"), place.get("place_url")
        if not isinstance(name, str) or not name.strip():
            return "invalid_place_fields"
        if not isinstance(address, str) or not address.strip():
            return "invalid_place_fields"
        if not isinstance(url, str) or not url.strip():
            return "invalid_place_fields"
        try:
            latitude, longitude = float(place["latitude"]), float(place["longitude"])
        except (KeyError, TypeError, ValueError):
            return "invalid_coordinates"
        if (
            not math.isfinite(latitude) or not math.isfinite(longitude)
            or not -90 <= latitude <= 90 or not -180 <= longitude <= 180
        ):
            return "invalid_coordinates"
        if cls._region_key(address) != cls._region_key(region):
            return "region_mismatch"
        return None

    def verify(
        self,
        hints: PlaceCandidateResponse,
        keywords: list[PreferenceKeyword],
        records: list[RecommendationRecord],
    ) -> PlaceCandidateResponse:
        region = self._region(records)
        if not region or not keywords:
            logger.info(
                "Kakao verification skipped missing_input region_present=%d keyword_count=%d",
                bool(region), len(keywords),
            )
            return PlaceCandidateResponse()
        if self._requires_key and not KAKAO_REST_API_KEY:
            raise AIConfigurationError("Kakao is not configured")

        visited_ids = {str(record.kakao_place_id) for record in records if record.kakao_place_id}
        visited_names = {
            self._local_name(record.place_name, region)
            for record in records if record.place_name
        }
        verified: list[PlaceCandidate] = []
        seen_ids: set[str] = set()
        seen_queries: set[str] = set()
        calls = 0
        counts = Counter()

        def lookup(query: str, purpose: str) -> list[dict]:
            nonlocal calls
            if calls >= self.MAX_CALLS:
                return []
            normalized_query = re.sub(r"[^\w]", "", query).casefold()
            if not normalized_query or normalized_query in seen_queries:
                counts["duplicate_query_count"] += 1
                return []
            seen_queries.add(normalized_query)
            calls += 1
            call_number = calls
            try:
                results = self._search(query)
                if not isinstance(results, list):
                    counts["invalid_api_response_count"] += 1
                    logger.error(
                        "Kakao verification call=%d purpose=%s http_status=200 invalid_response=1",
                        call_number, purpose,
                    )
                    raise AIResponseError("Invalid Kakao search response")
                counts["raw_result_count"] += len(results)
                logger.info(
                    "Kakao verification call=%d purpose=%s http_status=200 raw_result_count=%d",
                    call_number, purpose, len(results),
                )
                return results
            except httpx.HTTPError as exc:
                response = getattr(exc, "response", None)
                status = getattr(response, "status_code", "unknown")
                logger.error(
                    "Kakao verification call=%d purpose=%s http_status=%s outcome=provider_error",
                    call_number, purpose, status,
                )
                raise AIRequestError("Kakao place search failed") from exc
            except (KeyError, TypeError, ValueError) as exc:
                logger.error(
                    "Kakao verification call=%d purpose=%s http_status=200 outcome=invalid_response",
                    call_number, purpose,
                )
                raise AIResponseError("Invalid Kakao search response") from exc

        def add(place: dict, *, hint: PlaceCandidate | None = None) -> None:
            rejection = self._place_rejection_reason(place, region)
            if rejection:
                counts[rejection] += 1
                return

            place_id = place["kakao_place_id"].strip()
            if place_id in visited_ids:
                counts["visited_id_count"] += 1
                return
            if place_id in seen_ids:
                counts["duplicate_id_count"] += 1
                return

            name = place["name"].strip()
            local_name = self._local_name(name, region)
            if local_name in visited_names:
                counts["visited_name_count"] += 1
                return
            if hint is not None and local_name != self._local_name(hint.name, region):
                counts["place_name_mismatch_count"] += 1
                return

            seen_ids.add(place_id)
            category = str(place.get("category_name") or "").strip()
            summary = hint.summary if hint is not None else (
                f"Kakao Local category: {category}"
                if category else f"{region}의 카카오 장소 검색에서 확인된 장소"
            )
            verified.append(PlaceCandidate(
                kakao_place_id=place_id,
                name=name,
                address=place["address"].strip(),
                latitude=float(place["latitude"]),
                longitude=float(place["longitude"]),
                matched_keywords=(hint.matched_keywords if hint is not None else []),
                summary=summary,
                source_url=place["place_url"].strip(),
            ))
            counts["verified_count"] += 1

        for hint in hints.candidates[:self.MAX_WEB_HINTS]:
            if len(verified) >= 10 or calls >= self.MAX_CALLS:
                break
            clean_name = self._clean_hint_name(hint.name, region)
            if not clean_name:
                counts["empty_clean_hint_count"] += 1
                continue
            for place in lookup(f"{region} {clean_name}", "tavily_hint"):
                add(place, hint=hint)
                if len(verified) >= 10:
                    break

        if len(verified) < 3:
            for term in self._preference_queries(keywords)[:self.MAX_FALLBACK_KEYWORDS]:
                if len(verified) >= 10 or calls >= self.MAX_CALLS:
                    break
                for place in lookup(f"{region} {term}", "preference_fallback"):
                    add(place)
                    if len(verified) >= 10:
                        break

        logger.info(
            "Kakao verification totals calls=%d raw_results=%d invalid_place_fields=%d invalid_place_ids=%d "
            "invalid_coordinates=%d region_mismatch=%d place_name_mismatch=%d visited_ids=%d "
            "visited_names=%d duplicates=%d duplicate_queries=%d verified=%d",
            calls, counts["raw_result_count"], counts["invalid_place_fields"],
            counts["invalid_place_id"], counts["invalid_coordinates"], counts["region_mismatch"],
            counts["place_name_mismatch_count"], counts["visited_id_count"],
            counts["visited_name_count"], counts["duplicate_id_count"], counts["duplicate_query_count"], len(verified),
        )
        return PlaceCandidateResponse(candidates=verified)
