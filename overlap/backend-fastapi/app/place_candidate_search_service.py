"""Category-scoped Kakao POI discovery with conservative Tavily evidence checks."""

from __future__ import annotations

import hashlib
import html
import logging
import re
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from enum import Enum
from typing import Any, Callable
from urllib.parse import urlparse

import httpx
from pydantic import BaseModel, ConfigDict, Field, field_validator

from .config import KAKAO_REST_API_KEY, TAVILY_API_KEY
from .kakao import search_places
from .record_preference_analysis import (
    PlaceType,
    PreferenceFacet,
    RecordPreferenceAnalysis,
    RecommendationCategory,
)

logger = logging.getLogger("uvicorn.error")


class CategoryMatchStatus(str, Enum):
    CONFIRMED = "confirmed"
    VERIFICATION_REQUIRED = "verification_required"
    MISMATCH = "mismatch"
    UNKNOWN = "unknown"


class FeatureEvidenceStatus(str, Enum):
    CONFIRMED = "confirmed"
    INSUFFICIENT = "insufficient"
    PLACE_IDENTITY_UNVERIFIED = "place_identity_unverified"
    UNAVAILABLE = "unavailable"
    SKIPPED = "skipped"


class ProviderStatus(str, Enum):
    COMPLETE = "complete"
    PARTIAL = "partial"
    NO_RESULTS = "no_results"
    UNAVAILABLE = "unavailable"


class KakaoPlaceCandidate(BaseModel):
    """Stable internal mapping of Kakao Local keyword-search fields."""

    model_config = ConfigDict(extra="ignore")

    kakao_place_id: str = Field(pattern=r"^\d+$", min_length=1, max_length=100)
    place_name: str = Field(min_length=1, max_length=160)
    address: str = Field(min_length=1, max_length=255)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    category_group_code: str | None = Field(default=None, max_length=16)
    category_name: str | None = Field(default=None, max_length=240)
    place_url: str = Field(min_length=1, max_length=500)

    @field_validator("latitude", "longitude")
    @classmethod
    def finite_coordinates(cls, value: float) -> float:
        if not (float("-inf") < value < float("inf")):
            raise ValueError("coordinates must be finite")
        return value

    @classmethod
    def from_kakao_result(cls, item: dict[str, Any]) -> "KakaoPlaceCandidate":
        """Map either Kakao raw `documents[]` fields or the legacy helper fields."""
        if not isinstance(item, dict):
            raise ValueError("Kakao place must be an object")
        return cls(
            kakao_place_id=item.get("kakao_place_id", item.get("id")),
            place_name=item.get("name", item.get("place_name")),
            address=item.get("address") or item.get("road_address_name") or item.get("address_name"),
            latitude=item.get("latitude", item.get("y")),
            longitude=item.get("longitude", item.get("x")),
            category_group_code=item.get("category_group_code"),
            category_name=item.get("category_name") or None,
            place_url=item.get("place_url"),
        )


class PlaceCategoryClassification(BaseModel):
    requested_category: RecommendationCategory
    categories: list[RecommendationCategory] = Field(default_factory=list)
    status: CategoryMatchStatus
    evidence: list[str] = Field(default_factory=list)


class PreferenceEvidence(BaseModel):
    record_id: int
    preference: str = Field(min_length=1, max_length=80)
    status: FeatureEvidenceStatus
    evidence_text: str | None = Field(default=None, max_length=320)
    evidence_url: str | None = Field(default=None, max_length=1000)


class PlaceCandidateEvidence(BaseModel):
    place: KakaoPlaceCandidate
    classification: PlaceCategoryClassification
    preference_evidence: list[PreferenceEvidence] = Field(default_factory=list)
    feature_search_status: FeatureEvidenceStatus
    # Relative Kakao query provenance, used only as a tie-break for Tavily
    # verification and final B-level ordering. It is not proof of a feature.
    search_query_priority: int = Field(default=0, ge=0, le=6)


class CandidateSearchResult(BaseModel):
    category: RecommendationCategory
    region: str = Field(min_length=1, max_length=100)
    kakao_status: ProviderStatus
    tavily_status: ProviderStatus
    kakao_call_count: int = Field(ge=0, le=6)
    tavily_call_count: int = Field(ge=0, le=3)
    candidates: list[PlaceCandidateEvidence] = Field(default_factory=list, max_length=30)
    query_count: int = Field(default=0, ge=0, le=6)
    search_skip_reason: str | None = None
    kakao_cache_hit_count: int = Field(default=0, ge=0, le=6)
    kakao_empty_cache_hit_count: int = Field(default=0, ge=0, le=6)


_SPACE = re.compile(r"\s+")
_CATEGORY_SPLIT = re.compile(r"\s*[>＞/]\s*")
_TAG = re.compile(r"<[^>]*>")
_HTML_ENTITY = re.compile(r"&(?:amp|lt|gt|quot|apos|#\d+|#x[\da-f]+);", re.IGNORECASE)
_WORD = re.compile(r"[^\w]+", re.UNICODE)

_REGION_ALIASES = {
    "\uC804\uB0A8\uAD11\uC8FC\uD1B5\uD569\uD2B9\uBCC4\uC2DC": "\uAD11\uC8FC",
    "서울특별시": "서울", "서울시": "서울", "서울": "서울",
    "부산광역시": "부산", "부산시": "부산", "부산": "부산",
    "대구광역시": "대구", "대구시": "대구", "대구": "대구",
    "인천광역시": "인천", "인천시": "인천", "인천": "인천",
    "광주광역시": "광주", "광주시": "광주", "광주": "광주",
    "대전광역시": "대전", "대전시": "대전", "대전": "대전",
    "울산광역시": "울산", "울산시": "울산", "울산": "울산",
    "세종특별자치시": "세종", "세종시": "세종", "세종": "세종",
    "제주특별자치도": "제주", "제주시": "제주", "제주": "제주",
}

_CONTEXT_TERMS: dict[RecommendationCategory, tuple[str, ...]] = {
    RecommendationCategory.FOOD: ("음식점", "맛집"),
    RecommendationCategory.BAR: ("술집", "이자카야"),
    RecommendationCategory.CAFE: ("카페",),
    RecommendationCategory.NATURE: ("공원", "산책로"),
    RecommendationCategory.ACTIVITY: ("경기장", "문화시설"),
}

_BAR_TERMS = {"술집", "주점", "이자카야", "호프", "포차", "펍", "와인바", "칵테일바", "바"}
_NATURE_TERMS = ("공원", "산책로", "수목원", "자연명소", "자연관광", "산림욕장", "자연휴양림", "전망대")
_ACTIVITY_TERMS = ("경기장", "야구장", "농구장", "축구장", "공연장", "전시장", "박물관", "미술관", "문화체험", "문화시설", "체험관")
_CAFE_TERMS = ("카페", "커피전문점")
_FOOD_TERMS = ("음식점", "한식", "양식", "중식", "일식", "분식", "패스트푸드", "치킨", "고기", "레스토랑")
_KNOWN_NON_TARGET_CODES = {"PK6", "SC4", "AC5", "AD5", "BK9", "CS2", "HP8", "OL7", "PO3", "SW8", "AG2", "MT1"}

_QUERY_TERM_REDUCTIONS = {
    "유자하이볼": ("하이볼",),
    "과일하이볼": ("하이볼",),
    "칵테일": ("바",),
    "조용해서": ("조용한",),
    "조용하고": ("조용한",),
    "조용함": ("조용한",),
    "넓고": ("넓은",),
    "넓어서": ("넓은",),
    "넓음": ("넓은",),
    "넓은 실내": ("넓은",),
}


def _norm(value: str | None) -> str:
    return _SPACE.sub(" ", (value or "").casefold()).strip()


def _compact(value: str | None) -> str:
    return _WORD.sub("", _norm(value))


def _preference_key(value: str) -> str:
    normalized = _compact(value)
    for stem in ("조용", "넓", "아늑", "유자하이볼", "하이볼", "꼬치"):
        if normalized.startswith(_compact(stem)):
            return _compact(stem)
    return normalized


def _intent_key(value: str) -> str:
    """Collapse explicit query reductions into one preference intent."""
    normalized = _compact(value)
    for original, reductions in _QUERY_TERM_REDUCTIONS.items():
        reduction_keys = {_compact(item) for item in reductions}
        if normalized == _compact(original) or normalized in reduction_keys:
            return sorted(reduction_keys)[0]
    return _preference_key(value)


def _region_key(value: str | None) -> str:
    token = _norm(value).split(maxsplit=1)
    if not token:
        return ""
    return _REGION_ALIASES.get(token[0], token[0])


def _search_region(value: str | None) -> str:
    """Use a Kakao-friendly canonical province/city label in search text only."""
    parts = _norm(value).split()
    if not parts:
        return ""
    parts[0] = _REGION_ALIASES.get(parts[0], parts[0])
    return " ".join(parts)


def _locality_parts(address: str) -> list[str]:
    return [part for part in address.split()[:2] if len(part) >= 2]


def _url_is_safe(value: str | None) -> bool:
    if not value:
        return False
    parsed = urlparse(value.strip())
    return parsed.scheme == "https" and bool(parsed.hostname)


class KakaoCategoryClassifier:
    """Classify only from Kakao category path/code and Kakao place name."""

    @staticmethod
    def _segments(value: str | None) -> list[str]:
        return [segment.strip() for segment in _CATEGORY_SPLIT.split(value or "") if segment.strip()]

    @staticmethod
    def _has_bar_segment(segments: list[str]) -> bool:
        for segment in segments:
            normalized = _norm(segment)
            if normalized in _BAR_TERMS or any(term in normalized for term in ("이자카야", "호프", "포차", "펍", "와인바", "칵테일바")):
                return True
        return False

    @classmethod
    def classify(cls, place: KakaoPlaceCandidate,
                 requested: RecommendationCategory | str) -> PlaceCategoryClassification:
        requested = RecommendationCategory(requested)
        segments = cls._segments(place.category_name)
        joined = " ".join(segments)
        code = (place.category_group_code or "").upper()
        name = place.place_name
        source_evidence: list[str] = []
        categories: set[RecommendationCategory] = set()

        bar_detail = cls._has_bar_segment(segments)
        if bar_detail:
            categories.update((RecommendationCategory.BAR, RecommendationCategory.FOOD))
            source_evidence.append("kakao_category_name:bar_subcategory")
        elif code == "FD6":
            categories.add(RecommendationCategory.FOOD)
            source_evidence.append("kakao_category_group_code:FD6")
        elif any(term in joined for term in _FOOD_TERMS):
            categories.add(RecommendationCategory.FOOD)
            source_evidence.append("kakao_category_name:food")

        if code == "CE7" or any(term in joined for term in _CAFE_TERMS):
            categories.add(RecommendationCategory.CAFE)
            source_evidence.append("kakao_category:cafe")

        nature_path = any(term in joined for term in _NATURE_TERMS)
        if nature_path and (code in {"AT4", "CT1", ""} or "공원" in joined or "산책로" in joined):
            categories.add(RecommendationCategory.NATURE)
            source_evidence.append("kakao_category_name:nature_subcategory")

        activity_path = any(term in joined for term in _ACTIVITY_TERMS) or any(term in name for term in _ACTIVITY_TERMS)
        if activity_path and code not in {"FD6", "CE7", "PK6"}:
            categories.add(RecommendationCategory.ACTIVITY)
            source_evidence.append("kakao_category_or_place_name:activity_subcategory")

        if requested == RecommendationCategory.ALL:
            status = CategoryMatchStatus.CONFIRMED if categories else CategoryMatchStatus.UNKNOWN
        elif requested in categories:
            status = CategoryMatchStatus.CONFIRMED
        elif requested == RecommendationCategory.BAR and code == "FD6" and not bar_detail:
            status = CategoryMatchStatus.VERIFICATION_REQUIRED
            source_evidence.append("restaurant_group_requires_bar_subcategory")
        elif not categories and code in {"AT4", "CT1"}:
            if requested == RecommendationCategory.NATURE and code == "AT4":
                status = CategoryMatchStatus.VERIFICATION_REQUIRED
                source_evidence.append("tourist_attraction_requires_nature_subcategory")
            elif requested == RecommendationCategory.ACTIVITY and code == "CT1":
                status = CategoryMatchStatus.VERIFICATION_REQUIRED
                source_evidence.append("culture_group_requires_activity_subcategory")
            else:
                status = CategoryMatchStatus.MISMATCH
                source_evidence.append(f"kakao_category_group_code:{code}:outside_requested_domain")
        elif not categories and code in {"FD6", "CE7", ""}:
            status = CategoryMatchStatus.VERIFICATION_REQUIRED
            source_evidence.append("broad_or_missing_kakao_category")
        elif not categories and code in _KNOWN_NON_TARGET_CODES:
            status = CategoryMatchStatus.MISMATCH
            source_evidence.append(f"kakao_category_group_code:{code}:not_target_domain")
        elif categories:
            status = CategoryMatchStatus.MISMATCH
            source_evidence.append("known_category_does_not_match_requested_category")
        else:
            status = CategoryMatchStatus.UNKNOWN
            source_evidence.append("insufficient_category_evidence")

        return PlaceCategoryClassification(
            requested_category=requested,
            categories=sorted(categories, key=lambda value: value.value),
            status=status,
            evidence=source_evidence,
        )


class PlaceCandidateSearchService:
    """Search genuine Kakao POIs first, then verify preference details on Tavily."""

    MAX_KAKAO_CALLS = 6
    MAX_TAVILY_CALLS = 3
    MAX_CANDIDATES = 30
    MAX_TAVILY_CANDIDATES = 3
    KAKAO_TIMEOUT_SECONDS = 6.0
    TAVILY_TIMEOUT_SECONDS = 8.0
    CACHE_TTL_SECONDS = 300
    CACHE_MAX_ENTRIES = 256

    def __init__(self, *, kakao_search: Callable[..., list[dict[str, Any]]] | None = None,
                 tavily_post_json: Callable[..., Any] | None = None,
                 kakao_api_key: str | None = None, tavily_api_key: str | None = None,
                 clock: Callable[[], float] = time.monotonic) -> None:
        self.kakao_api_key = KAKAO_REST_API_KEY if kakao_api_key is None else kakao_api_key.strip()
        self.tavily_api_key = TAVILY_API_KEY if tavily_api_key is None else tavily_api_key.strip()
        self._kakao_search = kakao_search or search_places
        self._tavily_post_json = tavily_post_json or httpx.post
        self._clock = clock
        self._cache: dict[str, tuple[float, Any]] = {}
        self._cache_lock = threading.Lock()

    def _cache_get(self, key: str) -> Any | None:
        now = self._clock()
        with self._cache_lock:
            item = self._cache.get(key)
            if item and item[0] > now:
                return item[1]
            if item:
                self._cache.pop(key, None)
        return None

    def _cache_set(self, key: str, value: Any, ttl: float = CACHE_TTL_SECONDS) -> None:
        with self._cache_lock:
            if len(self._cache) >= self.CACHE_MAX_ENTRIES:
                oldest = min(self._cache, key=lambda item: self._cache[item][0])
                self._cache.pop(oldest, None)
            self._cache[key] = (self._clock() + ttl, value)

    @staticmethod
    def _specific_categories(category: RecommendationCategory,
                             preferences: list[RecordPreferenceAnalysis]) -> list[RecommendationCategory]:
        if category != RecommendationCategory.ALL:
            return [category]
        weights: dict[RecommendationCategory, float] = {}
        record_support: dict[RecommendationCategory, set[int]] = {}
        for analysis in preferences:
            has_liked_facet = False
            for facet in analysis.facets:
                if facet.polarity != "liked":
                    continue
                has_liked_facet = True
                specificity = 1.15 if facet.target_kind.value in {"menu", "drink", "food", "activity", "scenery"} else 0.85
                weight = analysis.emotion_intensity * facet.confidence * specificity
                for value in set(analysis.categories).intersection(facet.categories):
                    if value != RecommendationCategory.ALL:
                        weights[value] = weights.get(value, 0.0) + weight
                        record_support.setdefault(value, set()).add(analysis.record_id)
            # Analysis-provider failures retain trusted place types and emotion.
            # They can support a low-priority domain query without inventing facets.
            if not has_liked_facet and analysis.place_type != PlaceType.UNKNOWN:
                for value in analysis.categories:
                    if value != RecommendationCategory.ALL:
                        weights[value] = weights.get(value, 0.0) + analysis.emotion_intensity * 0.35
                        record_support.setdefault(value, set()).add(analysis.record_id)
        # Overlapping labels on a single record are not independent support.
        # Cap repeated facet contribution per record so one verbose record does
        # not dominate category selection.
        weights = {value: min(weight, 1.5 * max(1, len(record_support.get(value, ()))))
                   for value, weight in weights.items()}
        return sorted(weights, key=lambda value: (-weights[value], value.value))

    @staticmethod
    def _category_for_facet(analysis: RecordPreferenceAnalysis, requested: RecommendationCategory,
                            facet: PreferenceFacet) -> list[RecommendationCategory]:
        valid = [category for category in analysis.categories if category != RecommendationCategory.ALL]
        valid = [category for category in valid if category in facet.categories or not facet.categories]
        if requested != RecommendationCategory.ALL:
            return [requested] if requested in valid else []
        primary = {
            PlaceType.BAR: RecommendationCategory.BAR,
            PlaceType.CAFE: RecommendationCategory.CAFE,
            PlaceType.FOOD: RecommendationCategory.FOOD,
            PlaceType.NATURE: RecommendationCategory.NATURE,
            PlaceType.ACTIVITY: RecommendationCategory.ACTIVITY,
        }.get(analysis.place_type)
        if primary in valid:
            return [primary]
        if analysis.place_type == PlaceType.UNKNOWN:
            inferred = {
                "drink": RecommendationCategory.BAR,
                "activity": RecommendationCategory.ACTIVITY,
                "scenery": RecommendationCategory.NATURE,
                "space": RecommendationCategory.CAFE,
            }.get(facet.target_kind.value)
            if inferred in valid:
                return [inferred]
        return valid

    @staticmethod
    def _feature_search_terms(facet: PreferenceFacet) -> list[str]:
        terms: list[str] = []
        if facet.target_kind.value in {"menu", "drink", "food"}:
            target = facet.target_text.strip()
            if target and target not in {"\uC74C\uC2DD", "\uBA54\uB274", "\uC74C\uB8CC", "\uC220", "\uB9E4\uC7A5", "\uBD84\uC704\uAE30", "\uACF5\uAC04"}:
                terms.append(target)
        elif facet.target_kind.value in {"activity", "scenery"}:
            target = facet.target_text.strip()
            if target and len(target) >= 2:
                terms.append(target)
        for feature in facet.features:
            term = feature.strip()
            for prefix, form in (("\uC870\uC6A9", "\uC870\uC6A9\uD55C"), ("\uB113", "\uB113\uC740"), ("\uC544\uB291", "\uC544\uB291\uD55C"), ("\uCE5C\uC808", "\uCE5C\uC808\uD55C")):
                if term.startswith(prefix):
                    term = form
                    break
            generic = term.startswith(("\uB9DB\uC788", "\uC88B", "\uC544\uB984"))
            if term and not generic:
                terms.append(term)
        return list(dict.fromkeys(terms))

    @classmethod
    def _build_queries(cls, category: RecommendationCategory, region: str,
                       preferences: list[RecordPreferenceAnalysis]) -> list[str]:
        """Prioritize the strongest, most specific record facets across all fields."""
        search_region = _search_region(region)
        # Build one strongest, concrete query per independent preference intent,
        # then add reductions and broad fallbacks in later passes. This reserves
        # the six-call budget for distinct tastes before spending it on synonyms.
        intent_queries: dict[tuple[RecommendationCategory, str], tuple[float, str]] = {}
        reductions: list[tuple[float, str, RecommendationCategory, str]] = []
        broad: dict[RecommendationCategory, tuple[float, str]] = {}
        for specific in cls._specific_categories(category, preferences):
            contexts = list(_CONTEXT_TERMS.get(specific, ()))
            for analysis in preferences:
                matching_facets = [facet for facet in analysis.facets
                    if facet.polarity == "liked"
                    and specific in cls._category_for_facet(analysis, category, facet)]
                if not matching_facets:
                    if specific in analysis.categories and analysis.place_type != PlaceType.UNKNOWN:
                        type_context = {
                            PlaceType.BAR: "\uC774\uC790\uCE74\uC57C" if specific == RecommendationCategory.BAR else "\uC74C\uC2DD\uC810",
                            PlaceType.FOOD: "\uC74C\uC2DD\uC810",
                            PlaceType.CAFE: "\uCE74\uD398",
                            PlaceType.NATURE: "\uC0B0\uCC45\uB85C" if specific == RecommendationCategory.NATURE else "\uC790\uC5F0\uBA85\uC18C",
                            PlaceType.ACTIVITY: "\uBB38\uD654\uC2DC\uC124",
                        }.get(analysis.place_type, "")
                        context = type_context or (contexts[0] if contexts else specific.value)
                        key = (specific, f"type:{analysis.place_type.value}")
                        broad[key[0]] = max(broad.get(specific, (0.0, "")),
                                            (analysis.emotion_intensity * 0.35, f"{search_region} {context}"))
                    continue
                for facet in matching_facets:
                    type_context = {
                        PlaceType.BAR: "\uC774\uC790\uCE74\uC57C" if specific == RecommendationCategory.BAR else "\uC74C\uC2DD\uC810",
                        PlaceType.FOOD: "\uC74C\uC2DD\uC810",
                        PlaceType.CAFE: "\uCE74\uD398",
                        PlaceType.NATURE: "\uC0B0\uCC45\uB85C" if specific == RecommendationCategory.NATURE else "\uC790\uC5F0\uBA85\uC18C",
                        PlaceType.ACTIVITY: "\uBB38\uD654\uC2DC\uC124",
                        PlaceType.UNKNOWN: "",
                    }.get(analysis.place_type, "")
                    context = type_context or (contexts[0] if contexts else specific.value)
                    specificity = 1.15 if facet.target_kind.value in {"menu", "drink", "food", "activity", "scenery"} else 0.85
                    weight = analysis.emotion_intensity * facet.confidence * specificity
                    for term in cls._feature_search_terms(facet):
                        key = (specific, _intent_key(term))
                        query = f"{search_region} {term} {context}"
                        current = intent_queries.get(key)
                        if current is None or weight > current[0]:
                            intent_queries[key] = (weight, query)
                        for reduced in _QUERY_TERM_REDUCTIONS.get(term, ()):
                            reductions.append((weight * 0.85, f"{search_region} {reduced} {context}",
                                               specific, _intent_key(reduced)))
                    broad[specific] = max(broad.get(specific, (0.0, "")),
                                          (weight * 0.60, f"{search_region} {context}"))
        result: list[str] = []
        seen: set[str] = set()
        reduction_queries = sorted(
            ((weight, query) for weight, query, _, _ in reductions),
            key=lambda row: (-row[0], _compact(row[1])),
        )
        groups = [sorted(intent_queries.values(), key=lambda row: (-row[0], _compact(row[1]))),
                  reduction_queries,
                  sorted(broad.values(), key=lambda row: (-row[0], _compact(row[1])))]
        for query_group in groups:
            for _, query in query_group:
                query = _SPACE.sub(" ", query).strip()
                key = _compact(query)
                if key and key not in seen:
                    result.append(query)
                    seen.add(key)
                if len(result) >= cls.MAX_KAKAO_CALLS:
                    return result
        return result

    @staticmethod
    def _same_region(address: str, region: str) -> bool:
        address_parts = address.split()
        region_parts = _norm(region).split()
        if not address_parts or not region_parts or _region_key(address_parts[0]) != _region_key(region_parts[0]):
            return False
        # If the selected area includes a city/county/district, require the
        # Kakao address to match that component too. A province-only request
        # remains intentionally broad.
        if len(region_parts) > 1:
            return len(address_parts) > 1 and _norm(address_parts[1]) == _norm(region_parts[1])
        return True

    @staticmethod
    def _visited(place: KakaoPlaceCandidate, visited_place_ids: set[str], visited_place_names: set[str]) -> bool:
        return place.kakao_place_id in visited_place_ids or _compact(place.place_name) in {
            _compact(name) for name in visited_place_names
        }

    @staticmethod
    def _candidate_key(place: KakaoPlaceCandidate) -> str:
        return _compact(place.place_name)

    def _get_kakao(self, query: str) -> list[dict[str, Any]]:
        key = "kakao:" + hashlib.sha256(_compact(query).encode("utf-8")).hexdigest()
        cached = self._cache_get(key)
        if cached is not None:
            return list(cached)
        results = self._kakao_search(query, timeout=self.KAKAO_TIMEOUT_SECONDS)
        if not isinstance(results, list):
            raise ValueError("invalid Kakao search response")
        # Negative lookups are short-lived so a temporary empty result cannot
        # suppress a later recovery for the full positive-cache window.
        self._cache_set(key, list(results), ttl=30 if not results else self.CACHE_TTL_SECONDS)
        return results

    @staticmethod
    def _evidence_terms(facet: PreferenceFacet) -> list[str]:
        if facet.target_kind.value in {"menu", "drink", "food"}:
            return [facet.target_text]
        return facet.features or [facet.target_text]

    @staticmethod
    def _identity_matches(place: KakaoPlaceCandidate, document: dict[str, Any]) -> bool:
        title = html.unescape(_TAG.sub(" ", str(document.get("title") or "")))
        content = html.unescape(_TAG.sub(" ", str(document.get("content") or "")))
        expected_name = _compact(place.place_name)
        if not expected_name or len(expected_name) < 4 or expected_name in {"카페", "음식점", "식당", "술집", "공원", "문화시설", "경기장"}:
            return False
        # Keep the place name and locality in one result field. A title for one
        # branch plus a snippet mentioning another district is weak evidence.
        locality = _locality_parts(place.address)
        region_key = _region_key(locality[0] if locality else "")
        if not region_key:
            return False
        location_fields = [_compact(title), _compact(content)]
        return any(
            expected_name in field and region_key in field
            and (len(locality) <= 1 or _compact(locality[1]) in field)
            for field in location_fields
        )

    @staticmethod
    def _safe_result_url(value: Any) -> str | None:
        if not isinstance(value, str) or not _url_is_safe(value.strip()):
            return None
        return value.strip()

    def _tavily_for_place(self, place: KakaoPlaceCandidate, region: str,
                          facets: list[tuple[int, PreferenceFacet]]) -> tuple[list[PreferenceEvidence], FeatureEvidenceStatus]:
        unique_terms = list(dict.fromkeys(term for _, facet in facets for term in self._evidence_terms(facet)))
        unique_terms = [term for term in unique_terms if term.strip()][:4]
        query = _SPACE.sub(" ", f"{place.place_name} {region} {' '.join(_locality_parts(place.address)[1:])} {' '.join(unique_terms)}").strip()
        cache_key = self._tavily_cache_key(place, query)
        cached = self._cache_get(cache_key)
        if cached is None:
            if not self.tavily_api_key:
                return ([PreferenceEvidence(record_id=record_id, preference=term,
                                            status=FeatureEvidenceStatus.UNAVAILABLE)
                         for record_id, facet in facets for term in self._evidence_terms(facet)],
                        FeatureEvidenceStatus.UNAVAILABLE)
            try:
                response = self._tavily_post_json(
                    "https://api.tavily.com/search",
                    headers={"Authorization": f"Bearer {self.tavily_api_key}"},
                    json={"query": query, "search_depth": "basic", "max_results": 5},
                    timeout=self.TAVILY_TIMEOUT_SECONDS,
                )
                response.raise_for_status()
                data = response.json()
                documents = data.get("results", []) if isinstance(data, dict) else []
                if not isinstance(documents, list):
                    raise ValueError("invalid Tavily results")
                cached = documents[:5]
                self._cache_set(cache_key, cached, ttl=3600 if cached else 60)
            except (httpx.HTTPError, KeyError, TypeError, ValueError) as exc:
                logger.info("place feature evidence unavailable reason=%s", type(exc).__name__)
                unavailable = [PreferenceEvidence(record_id=record_id, preference=term,
                                                  status=FeatureEvidenceStatus.UNAVAILABLE)
                               for record_id, facet in facets for term in self._evidence_terms(facet)]
                return unavailable, FeatureEvidenceStatus.UNAVAILABLE

        identity_documents = [document for document in cached if isinstance(document, dict)
                              and self._identity_matches(place, document)]
        evidence_rows: list[PreferenceEvidence] = []
        invalid_url_count = 0
        for record_id, facet in facets:
            for term in self._evidence_terms(facet):
                needle = _compact(term)
                match = next((document for document in identity_documents
                              if needle and _preference_key(term) in _compact(
                                  html.unescape(_TAG.sub(" ", str(document.get("title") or ""))) + " " +
                                  html.unescape(_TAG.sub(" ", str(document.get("content") or ""))))), None)
                if match:
                    text = _SPACE.sub(" ", html.unescape(_TAG.sub(" ", str(match.get("content") or "")))).strip()
                    safe_url = self._safe_result_url(match.get("url"))
                    if not safe_url:
                        invalid_url_count += 1
                        evidence_rows.append(PreferenceEvidence(
                            record_id=record_id, preference=term, status=FeatureEvidenceStatus.INSUFFICIENT,
                        ))
                        continue
                    evidence_rows.append(PreferenceEvidence(
                        record_id=record_id,
                        preference=term,
                        status=FeatureEvidenceStatus.CONFIRMED,
                        evidence_text=text[:320],
                        evidence_url=safe_url,
                    ))
                elif identity_documents:
                    evidence_rows.append(PreferenceEvidence(
                        record_id=record_id, preference=term, status=FeatureEvidenceStatus.INSUFFICIENT,
                    ))
                else:
                    evidence_rows.append(PreferenceEvidence(
                        record_id=record_id, preference=term,
                        status=FeatureEvidenceStatus.PLACE_IDENTITY_UNVERIFIED,
                    ))
        overall = (FeatureEvidenceStatus.CONFIRMED if any(row.status == FeatureEvidenceStatus.CONFIRMED for row in evidence_rows)
                   else FeatureEvidenceStatus.INSUFFICIENT if identity_documents
                   else FeatureEvidenceStatus.PLACE_IDENTITY_UNVERIFIED)
        logger.info(
            "AI_RECOMMENDATION_TAVILY_EVIDENCE kakao_place_id=%s result_count=%d "
            "identity_match_count=%d evidence_term_count=%d confirmed_term_count=%d "
            "insufficient_term_count=%d invalid_url_count=%d overall_status=%s",
            place.kakao_place_id, len(cached), len(identity_documents), len(evidence_rows),
            sum(row.status == FeatureEvidenceStatus.CONFIRMED for row in evidence_rows),
            sum(row.status == FeatureEvidenceStatus.INSUFFICIENT for row in evidence_rows),
            invalid_url_count, overall.value,
        )
        return evidence_rows, overall

    @staticmethod
    def _tavily_cache_key(place: KakaoPlaceCandidate, query: str) -> str:
        return "tavily:" + hashlib.sha256((place.kakao_place_id + "|" + _compact(query)).encode("utf-8")).hexdigest()

    def _tavily_key_for(self, place: KakaoPlaceCandidate, region: str,
                        facets: list[tuple[int, PreferenceFacet]]) -> str:
        unique_terms = list(dict.fromkeys(term for _, facet in facets for term in self._evidence_terms(facet)))
        unique_terms = [term for term in unique_terms if term.strip()][:4]
        query = _SPACE.sub(" ", f"{place.place_name} {region} {' '.join(_locality_parts(place.address)[1:])} {' '.join(unique_terms)}").strip()
        return self._tavily_cache_key(place, query)

    def search(
        self,
        *,
        category: RecommendationCategory | str,
        region: str,
        preferences: list[RecordPreferenceAnalysis],
        visited_place_ids: set[str] | None = None,
        visited_place_names: set[str] | None = None,
    ) -> CandidateSearchResult:
        """Find Kakao POIs for an explicit region and attach bounded web evidence."""
        category = RecommendationCategory(category)
        input_region = region
        region = _norm(region)
        if not region:
            logger.info("AI_RECOMMENDATION_SEARCH_INPUT category=%s region_status=missing preferences=%d",
                        category.value, len(preferences))
            raise ValueError("region is required")
        if len(region) > 100:
            raise ValueError("region is too long")
        visited_place_ids = visited_place_ids or set()
        visited_place_names = visited_place_names or set()
        queries = self._build_queries(category, region, preferences)
        category_record_count = sum(
            category == RecommendationCategory.ALL or category in analysis.categories
            for analysis in preferences
        )
        usable_facet_count = sum(
            facet.polarity == "liked"
            and (category == RecommendationCategory.ALL or category in facet.categories)
            and (category == RecommendationCategory.ALL or category in analysis.categories)
            and any(value != RecommendationCategory.ALL for value in analysis.categories)
            and (not facet.categories or bool(set(facet.categories).intersection(analysis.categories)))
            for analysis in preferences for facet in analysis.facets
        )
        skip_reason = "no_supported_preference_query" if not queries else None
        logger.info(
            "AI_RECOMMENDATION_SEARCH_INPUT category=%s region_original=%r region_normalized=%r "
            "region_compare_key=%r region_changed=%s analysis_count=%d category_record_count=%d usable_facet_count=%d "
            "query_generation_attempted=1 generated_query_count=%d search_skip_reason=%s kakao_key_configured=%s",
            category.value, input_region[:100], region, _region_key(region), input_region != region, len(preferences),
            category_record_count, usable_facet_count, len(queries), skip_reason or "none",
            bool(self.kakao_api_key),
        )
        if not queries:
            return CandidateSearchResult(
                category=category, region=region, kakao_status=ProviderStatus.NO_RESULTS,
                tavily_status=ProviderStatus.NO_RESULTS, kakao_call_count=0,
                tavily_call_count=0, candidates=[], query_count=0,
                search_skip_reason=skip_reason,
            )
        if not self.kakao_api_key:
            return CandidateSearchResult(category=category, region=region, kakao_status=ProviderStatus.UNAVAILABLE,
                                         tavily_status=ProviderStatus.NO_RESULTS, kakao_call_count=0,
                                         tavily_call_count=0, candidates=[], query_count=len(queries),
                                         search_skip_reason="missing_kakao_configuration")

        candidate_by_id: dict[str, KakaoPlaceCandidate] = {}
        candidate_by_name: set[str] = set()
        classification_by_id: dict[str, PlaceCategoryClassification] = {}
        kakao_calls = 0
        kakao_cache_hits = 0
        kakao_empty_cache_hits = 0
        kakao_error = False
        category_mismatch_count = 0
        region_mismatch_count = 0
        candidate_query_priority: dict[str, int] = {}
        candidate_query_text: dict[str, str] = {}
        for query_index, query in enumerate(queries):
            if kakao_calls >= self.MAX_KAKAO_CALLS:
                break
            # _build_queries orders facet-specific queries by preference weight;
            # provenance is a retrieval tie-break only, never feature evidence.
            query_priority = len(queries) - query_index
            query_key = "kakao:" + hashlib.sha256(_compact(query).encode("utf-8")).hexdigest()
            cached_results = self._cache_get(query_key)
            cache_hit = cached_results is not None
            try:
                if cache_hit:
                    kakao_cache_hits += 1
                    if not cached_results:
                        kakao_empty_cache_hits += 1
                    results = list(cached_results)
                else:
                    kakao_calls += 1
                    results = self._get_kakao(query)
                for raw in results:
                    try:
                        place = KakaoPlaceCandidate.from_kakao_result(raw)
                    except (TypeError, ValueError):
                        continue
                    if not self._same_region(place.address, region):
                        region_mismatch_count += 1
                        continue
                    if self._visited(place, visited_place_ids, visited_place_names):
                        continue
                    classification = KakaoCategoryClassifier.classify(place, category)
                    if classification.status == CategoryMatchStatus.MISMATCH:
                        category_mismatch_count += 1
                        logger.info(
                            "AI recommendation candidate pipeline=category-v3 stage=kakao_category_filter "
                            "kakao_place_id=%s place_name=%r kakao_category=%r category_status=%s "
                            "decision=rejected reason=category_mismatch",
                            place.kakao_place_id,
                            " ".join(place.place_name.split())[:120],
                            " ".join((place.category_name or "").split())[:160] or "unavailable",
                            classification.status.value,
                        )
                        continue
                    if len(candidate_by_id) >= self.MAX_CANDIDATES:
                        break
                    name_key = self._candidate_key(place)
                    if place.kakao_place_id in candidate_by_id:
                        if query_priority > candidate_query_priority.get(place.kakao_place_id, 0):
                            candidate_query_priority[place.kakao_place_id] = query_priority
                            candidate_query_text[place.kakao_place_id] = query
                        continue
                    if name_key in candidate_by_name:
                        continue
                    candidate_by_id[place.kakao_place_id] = place
                    candidate_by_name.add(name_key)
                    classification_by_id[place.kakao_place_id] = classification
                    candidate_query_priority[place.kakao_place_id] = query_priority
                    candidate_query_text[place.kakao_place_id] = query
                if len(candidate_by_id) >= self.MAX_CANDIDATES:
                    break
            except RuntimeError as exc:
                logger.info("place Kakao search unavailable reason=%s", type(exc).__name__)
                kakao_error = True
                break
            except (httpx.HTTPError, KeyError, TypeError, ValueError) as exc:
                response = getattr(exc, "response", None)
                status = getattr(response, "status_code", None)
                category_name = (
                    "rate_limited" if status == 429 else
                    "authentication_or_authorization" if status in {401, 403} else
                    "invalid_request" if status == 400 else
                    "provider_server_error" if status is not None and status >= 500 else
                    "provider_http_error" if status is not None else "transport_or_payload_error"
                )
                logger.info("place Kakao search failed reason=%s http_status=%s provider_error_category=%s",
                            type(exc).__name__, status if status is not None else "none", category_name)
                kakao_error = True
                break

        kakao_status = (ProviderStatus.PARTIAL if kakao_error and candidate_by_id
                        else ProviderStatus.UNAVAILABLE if kakao_error
                        else ProviderStatus.COMPLETE if candidate_by_id
                        else ProviderStatus.NO_RESULTS)

        # Preserve each record/facet relation once, independent of object identity in output.
        facets_by_record_key: dict[tuple[int, str], tuple[int, PreferenceFacet]] = {}
        for analysis in preferences:
            for facet in analysis.facets:
                if self._category_for_facet(analysis, category, facet):
                    facets_by_record_key[(analysis.record_id, facet.model_dump_json())] = (analysis.record_id, facet)
        relevant_facets = list(facets_by_record_key.values())
        analysis_by_record = {analysis.record_id: analysis for analysis in preferences}

        def facet_priority(row):
            record_id, facet = row
            analysis = analysis_by_record.get(record_id)
            if analysis is None:
                return 0.0
            specificity = 1.15 if facet.target_kind.value in {"menu", "drink", "food", "activity", "scenery"} else 0.85
            return analysis.emotion_intensity * facet.confidence * specificity

        # Tavily has a fixed three-place budget; evaluate the strongest record
        # facets first so a long history cannot let early records consume terms.
        relevant_facets.sort(key=lambda row: (-facet_priority(row), row[0], row[1].target_text.casefold()))
        tavily_calls = 0
        tavily_cache_hits = 0
        tavily_skip_reason = None
        enriched: list[PlaceCandidateEvidence] = []
        tavily_had_error = False
        # Only Kakao-confirmed category matches are sent to Tavily; uncertain
        # category candidates remain visible with a verification-required state.
        candidate_facets_by_id: dict[str, list[tuple[int, PreferenceFacet]]] = {}
        for place_id, place in candidate_by_id.items():
            categories = set(classification_by_id[place_id].categories)
            category_facets = [row for row in relevant_facets if categories.intersection(row[1].categories)]
            query_key = _compact(candidate_query_text.get(place_id, ""))
            query_facets = []
            for row in category_facets:
                _, facet = row
                terms = self._feature_search_terms(facet)
                terms.extend(reduced for term in self._feature_search_terms(facet)
                             for reduced in _QUERY_TERM_REDUCTIONS.get(term, ()))
                if any(_compact(term) and _compact(term) in query_key for term in terms):
                    query_facets.append(row)
            candidate_facets_by_id[place_id] = query_facets or category_facets

        sorted_tavily_candidates = sorted(
            (place for place in candidate_by_id.values()
             if classification_by_id[place.kakao_place_id].status == CategoryMatchStatus.CONFIRMED
             and candidate_facets_by_id.get(place.kakao_place_id)),
            key=lambda place: (-candidate_query_priority.get(place.kakao_place_id, 0),
                               place.place_name.casefold(), place.kakao_place_id),
        )
        # Round-robin candidates from distinct Kakao query intents before
        # selecting additional candidates from any one intent.
        by_query: dict[int, list[KakaoPlaceCandidate]] = {}
        for place in sorted_tavily_candidates:
            by_query.setdefault(candidate_query_priority.get(place.kakao_place_id, 0), []).append(place)
        tavily_candidates: list[KakaoPlaceCandidate] = []
        for priority in sorted(by_query, reverse=True):
            if by_query[priority]:
                tavily_candidates.append(by_query[priority].pop(0))
                if len(tavily_candidates) == self.MAX_TAVILY_CANDIDATES:
                    break
        if len(tavily_candidates) < self.MAX_TAVILY_CANDIDATES:
            for priority in sorted(by_query, reverse=True):
                tavily_candidates.extend(by_query[priority][:self.MAX_TAVILY_CANDIDATES - len(tavily_candidates)])
                if len(tavily_candidates) == self.MAX_TAVILY_CANDIDATES:
                    break
        logger.info(
            "AI_RECOMMENDATION_TAVILY_SELECTION candidate_pool_count=%d selected_count=%d "
            "distinct_query_priority_count=%d",
            sum(classification_by_id[place.kakao_place_id].status == CategoryMatchStatus.CONFIRMED
                for place in candidate_by_id.values()),
            len(tavily_candidates), len({candidate_query_priority.get(place.kakao_place_id, 0)
                                         for place in tavily_candidates}),
        )
        evidence_by_id: dict[str, tuple[list[PreferenceEvidence], FeatureEvidenceStatus]] = {}
        if relevant_facets and tavily_candidates:
            cached_candidate_ids = {
                place.kakao_place_id for place in tavily_candidates
                if self._cache_get(self._tavily_key_for(place, region, candidate_facets_by_id[place.kakao_place_id])) is not None
            }
            external_keys = {
                place.kakao_place_id for place in tavily_candidates
                if self.tavily_api_key and self._cache_get(self._tavily_key_for(
                    place, region, candidate_facets_by_id[place.kakao_place_id])) is None
            }
            tavily_cache_hits = len(cached_candidate_ids)
            tavily_calls = min(len(external_keys), self.MAX_TAVILY_CALLS)
            if not self.tavily_api_key and len(cached_candidate_ids) < len(tavily_candidates):
                tavily_skip_reason = "missing_tavily_configuration"
            elif not external_keys:
                tavily_skip_reason = "tavily_result_cache_hit"
            with ThreadPoolExecutor(max_workers=min(3, len(tavily_candidates))) as executor:
                futures = {executor.submit(self._tavily_for_place, place, region,
                                           candidate_facets_by_id[place.kakao_place_id]): place.kakao_place_id
                           for place in tavily_candidates}
                for future, place_id in ((future, place_id) for future, place_id in futures.items()):
                    try:
                        rows, status = future.result()
                        evidence_by_id[place_id] = rows, status
                    except Exception as exc:
                        logger.info("place feature evidence failed reason=%s", type(exc).__name__)
                        tavily_had_error = True
                        evidence_by_id[place_id] = (
                            [PreferenceEvidence(record_id=record_id, preference=term, status=FeatureEvidenceStatus.UNAVAILABLE)
                             for record_id, facet in relevant_facets for term in self._evidence_terms(facet)],
                            FeatureEvidenceStatus.UNAVAILABLE,
                        )
        elif tavily_candidates and not relevant_facets:
            tavily_skip_reason = "no_relevant_preference_facets"
            for place in tavily_candidates:
                evidence_by_id[place.kakao_place_id] = ([], FeatureEvidenceStatus.SKIPPED)
        elif not tavily_candidates:
            tavily_skip_reason = (
                "no_category_confirmed_tavily_candidates" if candidate_by_id else "no_kakao_candidates"
            )

        logger.info(
            "AI_RECOMMENDATION_TAVILY_INPUT category=%s relevant_facet_count=%d "
            "category_confirmed_candidate_count=%d tavily_key_configured=%s "
            "result_cache_hit_count=%d external_call_count=%d skip_reason=%s",
            category.value, len(relevant_facets), len(tavily_candidates), bool(self.tavily_api_key),
            tavily_cache_hits, tavily_calls, tavily_skip_reason or "none",
        )

        for place in candidate_by_id.values():
            rows, status = evidence_by_id.get(
                place.kakao_place_id,
                ([], FeatureEvidenceStatus.SKIPPED if classification_by_id[place.kakao_place_id].status != CategoryMatchStatus.CONFIRMED
                 else FeatureEvidenceStatus.UNAVAILABLE if self.tavily_api_key else FeatureEvidenceStatus.UNAVAILABLE),
            )
            enriched.append(PlaceCandidateEvidence(
                place=place,
                classification=classification_by_id[place.kakao_place_id],
                preference_evidence=rows,
                feature_search_status=status,
                search_query_priority=candidate_query_priority.get(place.kakao_place_id, 0),
            ))

        if not candidate_by_id:
            tavily_status = ProviderStatus.NO_RESULTS
        elif not tavily_candidates:
            tavily_status = ProviderStatus.NO_RESULTS
        elif tavily_had_error or any(item.feature_search_status == FeatureEvidenceStatus.UNAVAILABLE for item in enriched):
            tavily_status = ProviderStatus.PARTIAL if any(item.feature_search_status == FeatureEvidenceStatus.CONFIRMED for item in enriched) else ProviderStatus.UNAVAILABLE
        elif any(item.feature_search_status == FeatureEvidenceStatus.CONFIRMED for item in enriched):
            tavily_status = ProviderStatus.COMPLETE
        else:
            tavily_status = ProviderStatus.PARTIAL

        logger.info("place candidate search complete category=%s kakao_calls=%d tavily_calls=%d candidates=%d",
                    category.value, kakao_calls, tavily_calls, len(enriched))
        evidence_confirmed_count = sum(
            row.status == FeatureEvidenceStatus.CONFIRMED
            for item in enriched for row in item.preference_evidence
        )
        identity_unverified_count = sum(
            row.status == FeatureEvidenceStatus.PLACE_IDENTITY_UNVERIFIED
            for item in enriched for row in item.preference_evidence
        )
        logger.info(
            "AI_RECOMMENDATION_TAVILY_RESULT candidate_count=%d confirmed_evidence_count=%d "
            "identity_unverified_count=%d",
            len(enriched), evidence_confirmed_count, identity_unverified_count,
        )
        if kakao_error:
            skip_reason = "kakao_provider_error"
        elif not candidate_by_id and kakao_empty_cache_hits and kakao_calls == 0:
            skip_reason = "cached_empty_kakao_results"
        elif not candidate_by_id and category_mismatch_count:
            skip_reason = "all_candidates_rejected_by_category_filter"
        elif not candidate_by_id and kakao_cache_hits:
            skip_reason = "cached_results_rejected_by_region_visited_or_validation"
        elif not candidate_by_id:
            skip_reason = "kakao_returned_no_candidates"
        else:
            skip_reason = None
        logger.info(
            "AI_RECOMMENDATION_SEARCH_RESULT category=%s generated_query_count=%d kakao_calls=%d "
            "kakao_cache_hit_count=%d kakao_empty_cache_hit_count=%d candidates=%d "
            "category_mismatch_count=%d region_mismatch_count=%d region_normalized=%r region_compare_key=%r "
            "search_skip_reason=%s kakao_status=%s",
            category.value, len(queries), kakao_calls, kakao_cache_hits, kakao_empty_cache_hits,
            len(enriched), category_mismatch_count, region_mismatch_count, region, _region_key(region),
            skip_reason or "none", kakao_status.value,
        )
        category_verified_count = sum(
            item.classification.status == CategoryMatchStatus.CONFIRMED for item in enriched
        )
        category_rejected_count = category_mismatch_count + sum(
            item.classification.status != CategoryMatchStatus.CONFIRMED for item in enriched
        )
        logger.info(
            "AI_RECOMMENDATION_DIAGNOSTIC event=kakao_category_filter pipeline=category-v3 category=%s "
            "kakao_category_verified_count=%d category_rejected_count=%d",
            category.value, category_verified_count, category_rejected_count,
        )
        enriched.sort(key=lambda item: {
            CategoryMatchStatus.CONFIRMED: 0,
            CategoryMatchStatus.VERIFICATION_REQUIRED: 1,
            CategoryMatchStatus.UNKNOWN: 2,
            CategoryMatchStatus.MISMATCH: 3,
        }[item.classification.status])
        return CandidateSearchResult(
            category=category,
            region=region,
            kakao_status=kakao_status,
            tavily_status=tavily_status,
            kakao_call_count=min(kakao_calls, self.MAX_KAKAO_CALLS),
            tavily_call_count=min(tavily_calls, self.MAX_TAVILY_CALLS),
            candidates=enriched,
            query_count=len(queries),
            search_skip_reason=skip_reason,
            kakao_cache_hit_count=kakao_cache_hits,
            kakao_empty_cache_hit_count=kakao_empty_cache_hits,
        )
