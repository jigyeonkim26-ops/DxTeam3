"""Category-scoped Kakao POI discovery with conservative Tavily evidence checks."""

from __future__ import annotations

import hashlib
import html
import logging
import re
import threading
import time
import contextvars
from concurrent.futures import ThreadPoolExecutor
from enum import Enum
from typing import Any, Callable, NamedTuple
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
    is_predicate_phrase,
)
from . import recommendation_diagnostics as diagnostics

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
    address_variants: list[str] = Field(default_factory=list, max_length=2)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    category_group_code: str | None = Field(default=None, max_length=16)
    category_name: str | None = Field(default=None, max_length=240)
    place_url: str = Field(min_length=1, max_length=500)
    phone: str | None = Field(default=None, max_length=40)

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
            address_variants=list(dict.fromkeys(
                value.strip() for value in (
                    item.get("address_name"), item.get("road_address_name"), item.get("address")
                ) if isinstance(value, str) and value.strip()
            ))[:2],
            latitude=item.get("latitude", item.get("y")),
            longitude=item.get("longitude", item.get("x")),
            category_group_code=item.get("category_group_code"),
            category_name=item.get("category_name") or None,
            place_url=item.get("place_url"),
            phone=(item.get("phone") or "").strip()[:40] or None,
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
    search_query_priority: int = Field(default=0, ge=0, le=12)


class CandidateSearchResult(BaseModel):
    category: RecommendationCategory
    region: str = Field(min_length=1, max_length=100)
    kakao_status: ProviderStatus
    tavily_status: ProviderStatus
    kakao_call_count: int = Field(ge=0, le=12)
    tavily_call_count: int = Field(ge=0, le=6)
    candidates: list[PlaceCandidateEvidence] = Field(default_factory=list, max_length=50)
    query_count: int = Field(default=0, ge=0, le=12)
    search_skip_reason: str | None = None
    kakao_cache_hit_count: int = Field(default=0, ge=0, le=12)
    kakao_empty_cache_hit_count: int = Field(default=0, ge=0, le=12)


_SPACE = re.compile(r"\s+")
_CATEGORY_SPLIT = re.compile(r"\s*[>＞/]\s*")
_TAG = re.compile(r"<[^>]*>")
_HTML_ENTITY = re.compile(r"&(?:amp|lt|gt|quot|apos|#\d+|#x[\da-f]+);", re.IGNORECASE)
_WORD = re.compile(r"[^\w]+", re.UNICODE)

_REGION_ALIASES = {
    # The 2026 integrated special city contains the former Gwangju urban
    # districts and separate counties such as Yeonggwang. Keep its canonical
    # jurisdiction distinct from the old urban-area aliases.
    "\uC804\uB0A8\uAD11\uC8FC\uD1B5\uD569\uD2B9\uBCC4\uC2DC": "\uC804\uB0A8\uAD11\uC8FC\uD1B5\uD569\uD2B9\uBCC4\uC2DC",
    "서울특별시": "서울", "서울시": "서울", "서울": "서울",
    "부산광역시": "부산", "부산시": "부산", "부산": "부산",
    "대구광역시": "대구", "대구시": "대구", "대구": "대구",
    "인천광역시": "인천", "인천시": "인천", "인천": "인천",
    "광주광역시": "\uC804\uB0A8\uAD11\uC8FC\uD1B5\uD569\uD2B9\uBCC4\uC2DC",
    "광주시": "\uC804\uB0A8\uAD11\uC8FC\uD1B5\uD569\uD2B9\uBCC4\uC2DC",
    "광주": "\uC804\uB0A8\uAD11\uC8FC\uD1B5\uD569\uD2B9\uBCC4\uC2DC",
    "대전광역시": "대전", "대전시": "대전", "대전": "대전",
    "울산광역시": "울산", "울산시": "울산", "울산": "울산",
    "세종특별자치시": "세종", "세종시": "세종", "세종": "세종",
    "제주특별자치도": "제주", "제주시": "제주", "제주": "제주",
}

_REGION_SEARCH_ALIASES = {
    **_REGION_ALIASES,
    "\uC804\uB0A8\uAD11\uC8FC\uD1B5\uD569\uD2B9\uBCC4\uC2DC": "\uAD11\uC8FC",
    "\uAD11\uC8FC\uAD11\uC5ED\uC2DC": "\uAD11\uC8FC",
    "\uAD11\uC8FC\uC2DC": "\uAD11\uC8FC",
    "\uAD11\uC8FC": "\uAD11\uC8FC",
}

_CONTEXT_TERMS: dict[RecommendationCategory, tuple[str, ...]] = {
    RecommendationCategory.FOOD: ("음식점", "맛집"),
    RecommendationCategory.BAR: ("술집", "이자카야"),
    RecommendationCategory.CAFE: ("카페",),
    RecommendationCategory.NATURE: ("산책로", "공원", "자연 명소", "수목원", "숲길", "등산로"),
    RecommendationCategory.ACTIVITY: ("경기장", "문화시설"),
}

_BAR_TERMS = {"술집", "주점", "이자카야", "호프", "포차", "펍", "와인바", "칵테일바", "바"}
_NATURE_TERMS = ("공원", "산책로", "수목원", "자연명소", "자연관광", "산림욕장", "자연휴양림", "전망대")
_NATURE_TERMS += ("등산로", "숲길", "자연관광지", "자연생태공원", "둘레길", "생태공원")
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
        if normalized == _compact(original):
            # Keep a user's exact, specific term distinct from its broader
            # retrieval fallback. The weaker form is suppressed when the
            # stronger intent already occupies the search budget.
            return normalized
        if normalized in reduction_keys:
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
    aliases = {"광주", "광주시", "광주광역시"}
    canonical = _region_key(parts[0])
    if parts[0] in aliases:
        parts[0] = "광주"
    elif canonical == "전남광주통합특별시":
        if len(parts) > 1 and parts[1] in aliases:
            parts = ["광주", *parts[2:]]
        elif len(parts) > 1 and parts[1].endswith("구"):
            parts = ["광주", *parts[1:]]
        elif len(parts) == 1:
            parts = ["광주"]
    else:
        parts[0] = _REGION_SEARCH_ALIASES.get(parts[0], parts[0])
    return " ".join(parts)


def _locality_parts(address: str) -> list[str]:
    parts = address.split()
    if not parts:
        return []
    area_index = 1
    aliases = {"광주", "광주시", "광주광역시"}
    if parts[0] == "전남광주통합특별시" and len(parts) > 1 and parts[1] in aliases:
        area_index = 2
    return [parts[0], parts[area_index]] if area_index < len(parts) else [parts[0]]


_GENERIC_PLACE_NAMES = {"카페", "음식점", "식당", "술집", "공원", "문화시설", "경기장"}
# Names shorter than this need a standalone-word or road-name match.
_SHORT_PLACE_NAME_LENGTH = 4
_ROAD_NAME = re.compile(r"\S+(?:로|길)$")


def _road_name(address: str) -> str:
    """Return the road segment of a road address (e.g. 상무중앙로), if any."""
    for part in address.split()[1:]:
        if _ROAD_NAME.fullmatch(part):
            return part
    return ""


# Words ending in 점 that are not branch names.
_NON_BRANCH_WORDS = {"점", "지점", "시점", "관점", "장점", "단점", "정점", "초점", "만점", "매점"}
# Evidence must sit near a mention of the place, so a "10 best restaurants"
# post cannot lend another venue's description to this candidate.
_EVIDENCE_WINDOW_CHARS = 250


class _IdentityContext(NamedTuple):
    base: str
    base_pattern: re.Pattern[str]
    branches: frozenset[str]
    requires_branch: bool
    aliases: frozenset[str]
    locality_key: str
    road_key: str
    phone_pattern: re.Pattern[str] | None

    def strong_signal(self, text: str, compact: str) -> bool:
        return ((len(self.road_key) >= 2 and self.road_key in compact)
                or bool(self.phone_pattern and self.phone_pattern.search(text)))


def _kakao_place_url_pattern(place_id: str) -> re.Pattern[str]:
    return re.compile(r"place\.map\.kakao\.com/(?:m/)?" + re.escape(place_id) + r"(?!\d)")


# Endings stripped (longest first) to compare a recorded word by its stem.
_PREFERENCE_ENDINGS = tuple(sorted((
    "스러운", "스럽고", "있어서", "있는", "했던", "했다", "해요", "해서", "하고", "하며", "로운",
    "한", "함", "이", "가", "은", "는", "을", "를", "고", "서", "던",
), key=len, reverse=True))
# Deliberately small groups of near-identical atmosphere words. Broader
# associations (e.g. 친절/서비스) would weaken what an A-grade claim means.
_PREFERENCE_SYNONYMS = (
    ("조용", "한적", "차분", "고요"),
    ("아늑", "포근"),
    ("넓", "여유", "쾌적"),
    ("깔끔", "청결"),
    ("전망", "경치", "조망"),
    ("노을", "석양", "일몰"),
)


def _preference_forms(value: str) -> set[str]:
    """Return the recorded word, its stem and close synonyms in compact form."""
    key = _compact(value)
    if not key:
        return set()
    forms = {key, _preference_key(value)}
    for ending in _PREFERENCE_ENDINGS:
        if key.endswith(ending) and len(key) - len(ending) >= 2:
            forms.add(key[:-len(ending)])
            break
    for group in _PREFERENCE_SYNONYMS:
        if any(form.startswith(member) for form in tuple(forms) for member in group):
            forms.update(group)
    return {form for form in forms if form}


# Province names: Kakao reads "광주 경기 …" as Gwangju-si in Gyeonggi-do.
_PROVINCE_NAMES = {"경기", "강원", "충북", "충남", "전북", "전남", "경북", "경남"}


def _query_term_usable(term: str, context: str) -> bool:
    """Whether a record term can narrow a Kakao keyword search.

    Rejects verdict sentences ("개맛있음"), terms already inside the
    place-type word ("경기" in "경기장") and region names, which Kakao treats
    as a location rather than a feature.
    """
    key = _compact(term)
    if not key or is_predicate_phrase(term) or key in _compact(context):
        return False
    region_names = {_compact(name) for name in _REGION_ALIASES} | _PROVINCE_NAMES
    return key not in region_names


def _query_mentions_term(query: str, term: str) -> bool:
    """True when the term's words appear as whole words in the query."""
    query_tokens = [_compact(token) for token in _norm(query).split()]
    term_tokens = [token for token in (_compact(part) for part in _norm(term).split()) if token]
    if not term_tokens:
        return False
    size = len(term_tokens)
    return any(query_tokens[index:index + size] == term_tokens
               for index in range(len(query_tokens) - size + 1))


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
            if any(term in joined for term in _FOOD_TERMS):
                source_evidence.append("kakao_category_name:food")
        elif any(term in joined for term in _FOOD_TERMS):
            categories.add(RecommendationCategory.FOOD)
            source_evidence.append("kakao_category_name:food")

        if code == "CE7":
            categories.add(RecommendationCategory.CAFE)
            source_evidence.append("kakao_category_group_code:CE7")
            if any(term in joined for term in _CAFE_TERMS):
                source_evidence.append("kakao_category_name:cafe")
        elif any(term in joined for term in _CAFE_TERMS):
            categories.add(RecommendationCategory.CAFE)
            source_evidence.append("kakao_category_name:cafe")

        nature_path = any(term in joined for term in _NATURE_TERMS)
        if nature_path and (code in {"AT4", "CT1", ""} or "공원" in joined or "산책로" in joined):
            categories.add(RecommendationCategory.NATURE)
            source_evidence.append("kakao_category_name:nature_subcategory")

        activity_category_path = any(term in joined for term in _ACTIVITY_TERMS)
        activity_name_path = any(term in name for term in _ACTIVITY_TERMS)
        activity_path = activity_category_path or activity_name_path
        if activity_path and code not in {"FD6", "CE7", "PK6"}:
            categories.add(RecommendationCategory.ACTIVITY)
            source_evidence.append(
                "kakao_category_name:activity_subcategory" if activity_category_path
                else "kakao_place_name:activity_subcategory"
            )

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

    MAX_KAKAO_CALLS = 12
    INITIAL_KAKAO_CALLS = 6
    MAX_CANDIDATES = 50
    MAX_CANDIDATES_PER_QUERY = 6
    EARLY_STOP_CANDIDATES = 8
    MAX_TAVILY_CALLS = 6
    MAX_TAVILY_CANDIDATES = 6
    INITIAL_TAVILY_CALLS = 3
    INITIAL_TAVILY_CANDIDATES = 3
    MAX_TAVILY_QUERY_TERMS = 2
    CITY_SPECIFIC_QUERIES = 3
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
        reduction_priority: dict[tuple[RecommendationCategory, str], float] = {}
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
                        if not _query_term_usable(term, context):
                            continue
                        key = (specific, _intent_key(term))
                        query = f"{search_region} {term} {context}"
                        current = intent_queries.get(key)
                        if current is None or weight > current[0]:
                            intent_queries[key] = (weight, query)
                        for reduced in _QUERY_TERM_REDUCTIONS.get(term, ()):
                            reduced_key = (specific, _intent_key(reduced))
                            reduction_priority[reduced_key] = max(
                                reduction_priority.get(reduced_key, 0.0), weight,
                            )
                            reductions.append((weight * 0.85, f"{search_region} {reduced} {context}",
                                               specific, _intent_key(reduced)))
                    broad[specific] = max(broad.get(specific, (0.0, "")),
                                          (weight * 0.60, f"{search_region} {context}"))
        result: list[str] = []
        seen: set[str] = set()
        shadowed = {
            key for key, priority in reduction_priority.items()
            if key in intent_queries and intent_queries[key][0] <= priority
        }
        intent_queries = {key: value for key, value in intent_queries.items() if key not in shadowed}
        reduction_queries = sorted(
            ((weight, query) for weight, query, specific, intent in reductions
             if (specific, intent) not in intent_queries and (specific, intent) not in shadowed),
            key=lambda row: (-row[0], _compact(row[1])),
        )
        # Interleave the strongest intent from each supported domain first.
        # A long food history can still contribute more searches, but cannot
        # occupy the entire first six-call batch before cafe/bar/activity.
        category_order = cls._specific_categories(category, preferences)
        intent_queues = {
            specific: sorted(
                (value for (query_category, _), value in intent_queries.items()
                 if query_category == specific),
                key=lambda row: (-row[0], _compact(row[1])),
            )
            for specific in category_order
        }
        intent_queries_ordered = []
        while any(intent_queues.values()):
            for specific in category_order:
                if intent_queues.get(specific):
                    intent_queries_ordered.append(intent_queues[specific].pop(0))
        # Reserve the next search batch for broader place-type retrieval. With
        # many Gemini facets, putting every exact facet before these fallbacks
        # can consume all 12 slots without ever trying a viable Kakao intent.
        primary_intents = intent_queries_ordered[:cls.INITIAL_KAKAO_CALLS]
        overflow_intents = intent_queries_ordered[cls.INITIAL_KAKAO_CALLS:]
        broad_queries = sorted(broad.values(), key=lambda row: (-row[0], _compact(row[1])))
        groups = [primary_intents]
        if overflow_intents:
            # When specific intents already exceed the first batch, prioritize
            # broad place retrieval before weaker synonym reductions.
            groups.append(broad_queries)
        if RecommendationCategory.NATURE in cls._specific_categories(category, preferences):
            nature_contexts = ("산책로", "공원", "자연 명소", "수목원", "숲길", "등산로")
            nature_weight = max((analysis.emotion_intensity for analysis in preferences
                                 if RecommendationCategory.NATURE in analysis.categories), default=0.2)
            nature_queries = [(nature_weight * 0.2, f"{search_region} {context}")
                              for context in nature_contexts]
        else:
            nature_queries = []
        if not overflow_intents:
            groups.extend([reduction_queries, broad_queries])
        groups.extend([nature_queries, reduction_queries if overflow_intents else [], overflow_intents])
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
    def _same_region(address: str, region: str, latitude: float | None = None,
                     longitude: float | None = None) -> bool:
        address_parts = address.split()
        region_parts = _norm(region).split()
        if not address_parts or not region_parts or _region_key(address_parts[0]) != _region_key(region_parts[0]):
            return False
        def area(parts: list[str]) -> str:
            if len(parts) < 2:
                return ""
            # Some Kakao address formats include the former core-city label
            # between the integrated city name and its autonomous district.
            offset = 2 if len(parts) > 2 and parts[1] in {"광주", "광주시", "광주광역시"} else 1
            return parts[offset] if offset < len(parts) else ""

        requested_area = area(region_parts)
        candidate_area = area(address_parts)
        core_city_alias = region_parts[0] in {"광주", "광주시", "광주광역시"}
        # Kakao's old and consolidated labels refer to the same core city, but
        # the administrative area still has to match. Coordinates are not
        # filtered through a hand-drawn rectangle: Kakao's administrative
        # address is authoritative and district/county comparison separates
        # the urban districts from distant counties such as Yeonggwang.
        if requested_area:
            # A district-qualified request (including an explicit one) stays
            # in that district. City-wide expansion uses the urban alias below.
            return _norm(candidate_area) == _norm(requested_area)
        if core_city_alias:
            return candidate_area.endswith("구")
        # A fully qualified integrated-city request may intentionally cover
        # its counties; the urban alias above remains limited to its five 구.
        return True

    @classmethod
    def _candidate_matches_region(cls, place: KakaoPlaceCandidate, region: str) -> bool:
        addresses = place.address_variants or [place.address]
        # If Kakao supplies both parcel and road addresses, both must agree
        # with the requested administrative scope. A disagreement is treated
        # as ambiguous provider data instead of trusting the more convenient
        # address string.
        return all(cls._same_region(address, region) for address in addresses)

    @staticmethod
    def _visited(place: KakaoPlaceCandidate, visited_place_ids: set[str], visited_place_names: set[str]) -> bool:
        return place.kakao_place_id in visited_place_ids or _compact(place.place_name) in {
            _compact(name) for name in visited_place_names
        }

    @staticmethod
    def _candidate_key(place: KakaoPlaceCandidate) -> str:
        # Keep distinct branches of the same chain. Kakao ID remains the
        # primary duplicate key; name plus locality only collapses exact repeats.
        return f"{_compact(place.place_name)}:{_compact(' '.join(_locality_parts(place.address)))}"

    @staticmethod
    def _kakao_cache_key(query: str) -> str:
        return "kakao:" + hashlib.sha256(_compact(query).encode("utf-8")).hexdigest()

    def _get_kakao(self, query: str) -> list[dict[str, Any]]:
        key = self._kakao_cache_key(query)
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
    def _document_text(document: dict[str, Any], key: str) -> str:
        return _norm(html.unescape(_TAG.sub(" ", str(document.get(key) or ""))))

    @staticmethod
    def _identity_fields(document: dict[str, Any]) -> list[tuple[str, str]]:
        """Return (normalized, compact) text for the title and the content."""
        fields = []
        for key in ("title", "content"):
            text = PlaceCandidateSearchService._document_text(document, key)
            fields.append((text, _compact(text)))
        return fields

    @staticmethod
    def _identity_context(place: KakaoPlaceCandidate) -> _IdentityContext | None:
        tokens = _norm(place.place_name).split()
        full_name = _compact(place.place_name)
        locality = _locality_parts(place.address)
        if len(full_name) < 2 or full_name in _GENERIC_PLACE_NAMES or not locality:
            return None
        canonical_region = _region_key(locality[0])
        aliases = {_compact(canonical_region)}
        if canonical_region == "전남광주통합특별시":
            aliases.update({"광주", "광주시", "광주광역시"})
        # "스타벅스 광주상무점" is often written "스타벅스 상무점": keep the
        # brand as the name and accept the branch with or without its city.
        branch = _compact(tokens[-1]) if len(tokens) > 1 and tokens[-1].endswith("점") else ""
        base = _compact(" ".join(tokens[:-1])) if branch else full_name
        if len(base) < 2 or base in _GENERIC_PLACE_NAMES:
            base, branch = full_name, ""
        branches = {branch} if branch else {"본점"}
        for alias in sorted(aliases, key=len, reverse=True):
            if branch.startswith(alias) and len(branch) - len(alias) >= 2:
                branches.add(branch[len(alias):])
                break
        road_key = next((_compact(_road_name(address))
                         for address in [place.address, *place.address_variants]
                         if _road_name(address)), "")
        phone_digits = re.sub(r"\D", "", place.phone or "")
        phone_pattern = (re.compile(r"(?<!\d)" + r"[\s.()\-]*".join(phone_digits) + r"(?!\d)")
                         if len(phone_digits) >= 8 else None)
        return _IdentityContext(
            base=base,
            base_pattern=re.compile(r"\s*".join(re.escape(char) for char in base)),
            branches=frozenset(branches),
            requires_branch=bool(branch) and branch != "본점",
            aliases=frozenset(aliases),
            locality_key=_compact(locality[1]) if len(locality) > 1 else "",
            road_key=road_key,
            phone_pattern=phone_pattern,
        )

    @staticmethod
    def _name_spans(context: _IdentityContext, text: str, compact: str) -> list[tuple[int, int]]:
        """Return the spans where this place (not another branch) is named."""
        if context.requires_branch and not any(branch in compact for branch in context.branches):
            return []
        short = len(context.base) < _SHORT_PLACE_NAME_LENGTH
        strong = context.strong_signal(text, compact)
        spans = []
        for match in context.base_pattern.finditer(text):
            start, end = match.span()
            following = re.match(r"\s*(\w+)", text[end:])
            next_word = following.group(1) if following else ""
            if next_word.endswith("점") and next_word not in _NON_BRANCH_WORDS:
                # "독도집 광주공원점" names another branch of the same brand.
                if _compact(next_word) in context.branches:
                    spans.append((start, end + following.end()))
                continue
            if short:
                # A short name such as "꾸다" also occurs inside other names
                # ("꾸다요"). Accept it only as a standalone word, or next to
                # this place's road name or phone number.
                attached = ((start > 0 and re.match(r"\w", text[start - 1]))
                            or re.match(r"\w", text[end:end + 1]))
                if attached and not strong:
                    continue
            spans.append((start, end))
        return spans

    @staticmethod
    def _identity_matches(place: KakaoPlaceCandidate, document: dict[str, Any]) -> bool:
        if _kakao_place_url_pattern(place.kakao_place_id).search(str(document.get("url") or "")):
            return True
        context = PlaceCandidateSearchService._identity_context(place)
        if context is None:
            return False
        # Keep the place name and its location in one result field. A title for
        # one branch plus a snippet mentioning another district is weak evidence.
        for text, compact in PlaceCandidateSearchService._identity_fields(document):
            if not PlaceCandidateSearchService._name_spans(context, text, compact):
                continue
            located = (any(alias in compact for alias in context.aliases)
                       and (not context.locality_key or context.locality_key in compact))
            if located or (context.phone_pattern and context.phone_pattern.search(text)):
                return True
        return False

    @staticmethod
    def _term_near_place(place: KakaoPlaceCandidate, document: dict[str, Any], forms: set[str]) -> bool:
        """True when a preference form appears near a mention of this place."""
        text = (PlaceCandidateSearchService._document_text(document, "title") + "\n"
                + PlaceCandidateSearchService._document_text(document, "content"))
        context = PlaceCandidateSearchService._identity_context(place)
        spans = (PlaceCandidateSearchService._name_spans(context, text, _compact(text))
                 if context else [])
        if not spans and _kakao_place_url_pattern(place.kakao_place_id).search(str(document.get("url") or "")):
            spans = [(0, len(text))]
        for start, end in spans:
            window = _compact(text[max(0, start - _EVIDENCE_WINDOW_CHARS):end + _EVIDENCE_WINDOW_CHARS])
            if any(form in window for form in forms):
                return True
        return False

    @staticmethod
    def _identity_diagnostic_details(place: KakaoPlaceCandidate, document: dict[str, Any]) -> dict[str, bool]:
        """Return boolean identity signals without retaining provider text."""
        context = PlaceCandidateSearchService._identity_context(place)
        identity = PlaceCandidateSearchService._identity_matches(place, document)
        if context is None:
            return {"place_name_match": identity, "region_match": False,
                    "locality_match": False, "identity_match": identity}
        fields = PlaceCandidateSearchService._identity_fields(document)
        return {
            "place_name_match": any(
                PlaceCandidateSearchService._name_spans(context, text, compact) for text, compact in fields
            ),
            "region_match": any(alias in compact for _, compact in fields for alias in context.aliases),
            "locality_match": not context.locality_key or any(
                context.locality_key in compact for _, compact in fields
            ),
            "identity_match": identity,
        }

    @staticmethod
    def _safe_result_url(value: Any) -> str | None:
        if not isinstance(value, str) or not _url_is_safe(value.strip()):
            return None
        return value.strip()

    @staticmethod
    def _tavily_query(place: KakaoPlaceCandidate, region: str, terms: list[str]) -> str:
        # Locate the place by its own address, not the user's search region:
        # a selected district can differ from the candidate's district.
        locality = _locality_parts(place.address)
        region_query = _search_region(" ".join(locality) if locality else region)
        return _SPACE.sub(" ", f"{place.place_name} {region_query} {' '.join(terms)}").strip()

    def _tavily_query_for(self, place: KakaoPlaceCandidate, region: str,
                          query_facets: list[tuple[int, PreferenceFacet]]) -> str:
        # Only terms that retrieved this candidate from Kakao go into the
        # query. Unrelated record terms pull results toward recipes and other
        # venues, so identity verification would never see this place.
        unique_terms = list(dict.fromkeys(term for _, facet in query_facets for term in self._evidence_terms(facet)))
        unique_terms = [term for term in unique_terms if term.strip()][:self.MAX_TAVILY_QUERY_TERMS]
        return self._tavily_query(place, region, unique_terms)

    def _tavily_for_place(self, place: KakaoPlaceCandidate, region: str,
                          facets: list[tuple[int, PreferenceFacet]],
                          query_facets: list[tuple[int, PreferenceFacet]]) -> tuple[list[PreferenceEvidence], FeatureEvidenceStatus]:
        query = self._tavily_query_for(place, region, query_facets)
        cache_key = self._tavily_cache_key(place, query)
        cached = self._cache_get(cache_key)
        cache_used = cached is not None
        request_status = "cache_hit" if cache_used else "response_ok"
        if cached is None:
            if not self.tavily_api_key:
                unavailable = [PreferenceEvidence(record_id=record_id, preference=term,
                                                  status=FeatureEvidenceStatus.UNAVAILABLE)
                               for record_id, facet in facets for term in self._evidence_terms(facet)]
                diagnostics.tavily_result(
                    place.kakao_place_id, request_status="missing_configuration", result_count=0,
                    identity_match_count=0, confirmed_term_count=0, invalid_url_count=0,
                    place_name_match=False, region_match=False, locality_match=False,
                    cache_used=False, rejection_reason="provider_unavailable",
                )
                return unavailable, FeatureEvidenceStatus.UNAVAILABLE
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
                diagnostics.tavily_result(
                    place.kakao_place_id, request_status="error", result_count=0,
                    identity_match_count=0, confirmed_term_count=0, invalid_url_count=0,
                    place_name_match=False, region_match=False, locality_match=False,
                    cache_used=False, rejection_reason="provider_unavailable",
                )
                return unavailable, FeatureEvidenceStatus.UNAVAILABLE

        result_documents = [document for document in cached if isinstance(document, dict)]
        identity_details = [self._identity_diagnostic_details(place, document) for document in result_documents]
        if diagnostics.enabled():
            # Development-only measurement: the query carries record terms and
            # titles are provider text, so this never runs outside diagnostics.
            logger.info(
                "AI_RECOMMENDATION_TAVILY_DEBUG kakao_place_id=%s place_name=%r address=%r "
                "compact_name=%r query=%r cache_used=%d",
                place.kakao_place_id, place.place_name, place.address,
                _compact(place.place_name), query, int(cache_used),
            )
            for index, (document, details) in enumerate(zip(result_documents, identity_details), start=1):
                logger.info(
                    "AI_RECOMMENDATION_TAVILY_DEBUG_RESULT kakao_place_id=%s index=%d "
                    "name_match=%d region_match=%d locality_match=%d identity_match=%d "
                    "title=%r url=%r",
                    place.kakao_place_id, index, int(details["place_name_match"]),
                    int(details["region_match"]), int(details["locality_match"]),
                    int(details["identity_match"]),
                    " ".join(html.unescape(_TAG.sub(" ", str(document.get("title") or ""))).split())[:120],
                    str(document.get("url") or "")[:200],
                )
        identity_documents = [document for document, details in zip(result_documents, identity_details)
                              if details["identity_match"]]
        evidence_rows: list[PreferenceEvidence] = []
        invalid_url_count = 0
        for record_id, facet in facets:
            for term in self._evidence_terms(facet):
                # The recorded term stays the evidence key (A-grade linking
                # matches it against the facet); only the lookup is widened.
                forms = _preference_forms(term)
                match = next((document for document in identity_documents
                              if forms and self._term_near_place(place, document, forms)), None)
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
        confirmed_term_count = sum(row.status == FeatureEvidenceStatus.CONFIRMED for row in evidence_rows)
        if confirmed_term_count:
            rejection_reason = "feature_confirmed"
        elif not identity_documents:
            rejection_reason = "place_identity_not_verified"
        elif invalid_url_count:
            rejection_reason = "unsafe_or_missing_evidence_url"
        else:
            rejection_reason = "preference_feature_not_found"
        diagnostics.tavily_result(
            place.kakao_place_id, request_status=request_status, result_count=len(cached),
            identity_match_count=len(identity_documents), confirmed_term_count=confirmed_term_count,
            invalid_url_count=invalid_url_count,
            place_name_match=any(item["place_name_match"] for item in identity_details),
            region_match=any(item["region_match"] for item in identity_details),
            locality_match=any(item["locality_match"] for item in identity_details),
            cache_used=cache_used, rejection_reason=rejection_reason,
        )
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
                        query_facets: list[tuple[int, PreferenceFacet]]) -> str:
        return self._tavily_cache_key(place, self._tavily_query_for(place, region, query_facets))

    def search(
        self,
        *,
        category: RecommendationCategory | str,
        region: str,
        preferences: list[RecordPreferenceAnalysis],
        visited_place_ids: set[str] | None = None,
        visited_place_names: set[str] | None = None,
        allow_region_expansion: bool = False,
        query_offset: int = 0,
        kakao_call_budget: int | None = None,
        tavily_call_budget: int | None = None,
        tavily_candidate_budget: int | None = None,
    ) -> CandidateSearchResult:
        """Find Kakao POIs for an explicit region and attach bounded web evidence."""
        category = RecommendationCategory(category)
        input_region = region
        region = _norm(region)
        diagnostics.set_flag("tavily_key_configured", bool(self.tavily_api_key))
        started_at = time.perf_counter()
        if not region:
            logger.info("AI_RECOMMENDATION_SEARCH_INPUT category=%s region_status=missing preferences=%d",
                        category.value, len(preferences))
            raise ValueError("region is required")
        if len(region) > 100:
            raise ValueError("region is too long")
        visited_place_ids = visited_place_ids or set()
        visited_place_names = visited_place_names or set()
        all_region_queries = self._build_queries(category, region, preferences)
        initial_queries = all_region_queries[:self.INITIAL_KAKAO_CALLS]
        query_regions = [region] * len(all_region_queries)
        queries = list(all_region_queries)
        region_parts = region.split()
        if allow_region_expansion and len(region_parts) > 1:
            is_gwangju_core_scope = (
                _region_key(region_parts[0]) == "전남광주통합특별시"
                and (region_parts[1] in {"광주", "광주시", "광주광역시"}
                     or region_parts[1].endswith("구"))
            )
            city_region = "광주" if is_gwangju_core_scope else ""
            broader_queries = self._build_queries(category, city_region, preferences) if city_region else []
            # The first six broader queries are still the most specific facets.
            # District-scoped term queries often find nothing, so retry the
            # strongest few city-wide (only these can link a candidate to a
            # recorded term), then spend the rest on the generalization tail so
            # a rich profile does not use every call on narrow combinations.
            if broader_queries:
                specific = broader_queries[:self.INITIAL_KAKAO_CALLS]
                city_prefix = _search_region(city_region) + " "
                district_prefix = _search_region(region) + " "

                def district_outcome(query: str) -> int:
                    # Prefer terms whose district search found places (they
                    # were only outside the district), then untried terms;
                    # a term with no places even in the district goes last.
                    if not query.startswith(city_prefix):
                        return 1
                    cached = self._cache_get(self._kakao_cache_key(
                        district_prefix + query[len(city_prefix):]))
                    return 1 if cached is None else 0 if cached else 2

                specific = sorted(specific, key=district_outcome)
                broader_queries = (specific[:self.CITY_SPECIFIC_QUERIES]
                                   + broader_queries[self.INITIAL_KAKAO_CALLS:]
                                   + specific[self.CITY_SPECIFIC_QUERIES:])
            queries = list(initial_queries)
            query_regions = [region] * len(queries)
            seen_queries = {_compact(query) for query in queries}
            for query in broader_queries:
                if len(queries) >= self.MAX_KAKAO_CALLS:
                    break
                if _compact(query) not in seen_queries:
                    queries.append(query)
                    query_regions.append(city_region)
                    seen_queries.add(_compact(query))
        query_offset = max(0, min(int(query_offset), len(queries)))
        queries = queries[query_offset:]
        query_regions = query_regions[query_offset:]
        kakao_call_budget = self.MAX_KAKAO_CALLS if kakao_call_budget is None else max(0, min(int(kakao_call_budget), self.MAX_KAKAO_CALLS))
        tavily_call_budget = self.MAX_TAVILY_CALLS if tavily_call_budget is None else max(0, min(int(tavily_call_budget), self.MAX_TAVILY_CALLS))
        tavily_candidate_budget = self.MAX_TAVILY_CANDIDATES if tavily_candidate_budget is None else max(0, min(int(tavily_candidate_budget), self.MAX_TAVILY_CANDIDATES))
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
        query_category_terms: dict[str, set[str]] = {}
        for analysis in preferences:
            for facet in analysis.facets:
                if facet.polarity != "liked":
                    continue
                categories = {item.value for item in facet.categories if item != RecommendationCategory.ALL}
                if not categories:
                    categories = {item.value for item in analysis.categories if item != RecommendationCategory.ALL}
                terms = self._feature_search_terms(facet)
                for term in terms:
                    compact_term = _compact(term)
                    if compact_term:
                        query_category_terms.setdefault(compact_term, set()).update(categories)
        skip_reason = "no_supported_preference_query" if not queries else None
        region_parts = region.split()
        search_region = _search_region(region)
        query_intent_counts = {
            "nature": sum(any(term in _compact(query) for term in map(_compact, _NATURE_TERMS))
                           for query in queries),
            "food": sum(any(term in _compact(query) for term in map(_compact, _FOOD_TERMS))
                        for query in queries),
            "activity": sum(any(term in _compact(query) for term in map(_compact, _ACTIVITY_TERMS))
                            for query in queries),
            "cafe": sum(any(term in _compact(query) for term in map(_compact, _CAFE_TERMS))
                        for query in queries),
        }
        diagnostics.add_count("generated_queries", len(queries))
        # This is request-wide analysis input: the continuation search sees the
        # same facets and must not double the unique preference count.
        diagnostics.set_count("searchable_positive_facets", usable_facet_count)
        generated_by_category = {item.value: 0 for item in RecommendationCategory if item != RecommendationCategory.ALL}
        for query in queries:
            compact_query = _compact(query)
            matched_categories = set().union(*(values for term, values in query_category_terms.items()
                                               if term and term in compact_query)) if query_category_terms else set()
            for category_name in matched_categories:
                generated_by_category[category_name] = generated_by_category.get(category_name, 0) + 1
        for category_name, count in generated_by_category.items():
            diagnostics.add_count(f"generated_queries_category_{category_name}", count)
        for intent, count in query_intent_counts.items():
            diagnostics.add_count(f"generated_queries_{intent}", count)
        logger.info(
            "AI_RECOMMENDATION_SEARCH_INPUT category=%s region_scope_level=%s region_alias_normalized=%s "
            "region_changed=%s analysis_count=%d category_record_count=%d usable_facet_count=%d "
            "generated_query_count=%d query_intent_distribution=%s region_search_stage_count=%d "
            "search_skip_reason=%s kakao_key_configured=%s",
            category.value, "district" if len(region_parts) > 1 else "city_or_province",
            bool(region_parts and search_region.split()[0] != region_parts[0]),
            input_region != region, len(preferences), category_record_count, usable_facet_count,
            len(queries), ",".join(f"{key}={value}" for key, value in query_intent_counts.items()),
            len(set(query_regions)), skip_reason or "none", bool(self.kakao_api_key),
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
        visited_excluded_count = 0
        duplicate_excluded_count = 0
        kakao_raw_candidate_count = 0
        queries_attempted = 0
        budget_exhausted = False
        candidate_pool_full = False
        candidate_query_priority: dict[str, int] = {}
        candidate_query_text: dict[str, str] = {}
        candidate_queries: dict[str, list[str]] = {}
        kakao_started_at = time.perf_counter()
        for query_index, query in enumerate(queries):
            if kakao_calls >= kakao_call_budget:
                budget_exhausted = True
                diagnostics.set_flag("kakao_call_budget_exhausted")
                break
            queries_attempted += 1
            diagnostics.add_count("kakao_query_characters_total", len(query))
            diagnostics.max_count("kakao_query_characters_max", len(query))
            if len(query) >= 80:
                diagnostics.add_count("kakao_long_queries_80_plus")
            # _build_queries orders facet-specific queries by preference weight;
            # provenance is a retrieval tie-break only, never feature evidence.
            query_priority = len(queries) - query_index
            compact_query = _compact(query)
            matched_categories = set().union(*(values for term, values in query_category_terms.items()
                                               if term and term in compact_query)) if query_category_terms else set()
            if not matched_categories:
                diagnostics.add_count("executed_queries_category_unknown")
            for category_name in matched_categories:
                diagnostics.add_count(f"executed_queries_category_{category_name}")
            query_key = self._kakao_cache_key(query)
            cached_results = self._cache_get(query_key)
            cache_hit = cached_results is not None
            try:
                if cache_hit:
                    kakao_cache_hits += 1
                    diagnostics.add_count("kakao_query_cache_hits")
                    if not cached_results:
                        kakao_empty_cache_hits += 1
                    results = list(cached_results)
                else:
                    kakao_calls += 1
                    diagnostics.add_count("kakao_external_calls")
                    results = self._get_kakao(query)
                kakao_raw_candidate_count += len(results)
                if diagnostics.enabled():
                    # Development-only: query text carries record terms.
                    logger.info(
                        "AI_RECOMMENDATION_KAKAO_QUERY_DEBUG query_priority=%d query=%r "
                        "raw_result_count=%d cache_hit=%d",
                        query_priority, query, len(results), int(cache_hit),
                    )
                if not results:
                    diagnostics.add_count("kakao_empty_result_queries")
                    if not cache_hit:
                        diagnostics.add_count("kakao_empty_external_responses")
                    if matched_categories:
                        for category_name in matched_categories:
                            diagnostics.add_count(f"kakao_empty_result_queries_category_{category_name}")
                    else:
                        diagnostics.add_count("kakao_empty_result_queries_category_unknown")
                for category_name in matched_categories:
                    diagnostics.add_count(f"kakao_raw_candidates_category_{category_name}", len(results))
                for raw in results:
                    raw_id = raw.get("id", raw.get("kakao_place_id")) if isinstance(raw, dict) else None
                    if raw_id is not None:
                        diagnostics.count_unique("kakao_unique_raw_places", str(raw_id))
                    try:
                        place = KakaoPlaceCandidate.from_kakao_result(raw)
                    except (TypeError, ValueError):
                        diagnostics.add_count("excluded_invalid_kakao_candidate")
                        continue
                    if not self._candidate_matches_region(place, query_regions[query_index]):
                        region_mismatch_count += 1
                        diagnostics.add_count("excluded_region")
                        diagnostics.count_unique("excluded_region_unique_places", place.kakao_place_id)
                        diagnostics.decision("region_filter", place.kakao_place_id, "rejected", "region_mismatch")
                        continue
                    if self._visited(place, visited_place_ids, visited_place_names):
                        visited_excluded_count += 1
                        diagnostics.add_count("excluded_visited")
                        diagnostics.decision("visited_filter", place.kakao_place_id, "rejected", "previously_visited")
                        continue
                    classification = KakaoCategoryClassifier.classify(place, category)
                    if classification.status == CategoryMatchStatus.MISMATCH:
                        category_mismatch_count += 1
                        diagnostics.add_count("excluded_category")
                        diagnostics.decision("category_filter", place.kakao_place_id, "rejected", "category_mismatch")
                        logger.info(
                            "AI recommendation candidate pipeline=category-v5 stage=kakao_category_filter "
                            "kakao_place_id=%s place_name=%r kakao_category=%r category_status=%s "
                            "decision=rejected reason=category_mismatch",
                            place.kakao_place_id,
                            " ".join(place.place_name.split())[:120],
                            " ".join((place.category_name or "").split())[:160] or "unavailable",
                            classification.status.value,
                        )
                        continue
                    if len(candidate_by_id) >= self.MAX_CANDIDATES:
                        candidate_pool_full = True
                        break
                    name_key = self._candidate_key(place)
                    if place.kakao_place_id in candidate_by_id:
                        diagnostics.add_count("duplicate_id_candidates")
                        diagnostics.decision("deduplicate", place.kakao_place_id, "merged", "duplicate_kakao_id")
                        if query_priority > candidate_query_priority.get(place.kakao_place_id, 0):
                            candidate_query_priority[place.kakao_place_id] = query_priority
                            candidate_query_text[place.kakao_place_id] = query
                        # Keep every query that found the place: a broad query
                        # must not erase the link to a term query ("하이볼 술집").
                        candidate_queries.setdefault(place.kakao_place_id, []).append(query)
                        continue
                    if name_key in candidate_by_name:
                        duplicate_excluded_count += 1
                        diagnostics.add_count("excluded_duplicate_name")
                        diagnostics.decision("deduplicate", place.kakao_place_id, "rejected", "duplicate_name")
                        continue
                    candidate_by_id[place.kakao_place_id] = place
                    candidate_by_name.add(name_key)
                    classification_by_id[place.kakao_place_id] = classification
                    diagnostics.decision("kakao_candidate", place.kakao_place_id, "accepted", "passed_search_filters")
                    candidate_query_priority[place.kakao_place_id] = query_priority
                    candidate_query_text[place.kakao_place_id] = query
                    candidate_queries[place.kakao_place_id] = [query]
                    per_query_count = sum(value == query_priority for value in candidate_query_priority.values())
                    if per_query_count >= self.MAX_CANDIDATES_PER_QUERY:
                        break
                if len(candidate_by_id) >= self.MAX_CANDIDATES:
                    candidate_pool_full = True
                    break
            except RuntimeError as exc:
                logger.info("place Kakao search unavailable reason=%s", type(exc).__name__)
                kakao_error = True
                diagnostics.error("kakao", type(exc).__name__)
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
                diagnostics.error("kakao", category_name)
                if isinstance(exc, httpx.TimeoutException):
                    diagnostics.set_flag("kakao_timeout")
                break

        diagnostics.stage("kakao_provider", int((time.perf_counter() - kakao_started_at) * 1000))
        if kakao_calls >= kakao_call_budget:
            diagnostics.set_flag("kakao_call_budget_exhausted")

        kakao_status = (ProviderStatus.PARTIAL if kakao_error and candidate_by_id
                        else ProviderStatus.UNAVAILABLE if kakao_error
                        else ProviderStatus.COMPLETE if candidate_by_id
                        else ProviderStatus.NO_RESULTS)
        diagnostics.add_count("kakao_raw_candidates", kakao_raw_candidate_count)
        # `kakao_unique_raw_places` is emitted from the request-scoped opaque-ID set.
        diagnostics.add_count("kakao_candidates_after_filters", len(candidate_by_id))
        for place_id in candidate_by_id:
            diagnostics.count_unique("kakao_unique_candidates_after_filters", place_id)
        diagnostics.add_count("executed_queries", queries_attempted)
        unexecuted_queries = max(0, len(queries) - queries_attempted)
        diagnostics.add_count("unexecuted_queries", unexecuted_queries)
        diagnostics.add_count("unexecuted_queries_budget", unexecuted_queries if budget_exhausted else 0)
        diagnostics.add_count("unexecuted_queries_early_stop", unexecuted_queries if not budget_exhausted else 0)
        if candidate_pool_full:
            diagnostics.set_flag("candidate_pool_cap_reached")
        diagnostics.add_count("kakao_calls", kakao_calls)

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

        # Tavily has a fixed six-place budget; evaluate the strongest record
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
        # Facets linked to the Kakao query that found the candidate. Only these
        # shape the Tavily query; the broader category facets are still checked
        # against identity-verified documents.
        query_facets_by_id: dict[str, list[tuple[int, PreferenceFacet]]] = {}
        for place_id, place in candidate_by_id.items():
            categories = set(classification_by_id[place_id].categories)
            category_facets = [row for row in relevant_facets if categories.intersection(row[1].categories)]
            found_by = candidate_queries.get(place_id, [])
            query_facets = []
            for row in category_facets:
                _, facet = row
                terms = self._feature_search_terms(facet)
                terms.extend(reduced for term in self._feature_search_terms(facet)
                             for reduced in _QUERY_TERM_REDUCTIONS.get(term, ()))
                # Whole-word match: "경기" must not link via "경기장".
                if any(_query_mentions_term(query, term) for query in found_by for term in terms):
                    query_facets.append(row)
            candidate_facets_by_id[place_id] = query_facets or category_facets
            query_facets_by_id[place_id] = query_facets

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
        if tavily_candidate_budget:
            for priority in sorted(by_query, reverse=True):
                if by_query[priority]:
                    tavily_candidates.append(by_query[priority].pop(0))
                    if len(tavily_candidates) == tavily_candidate_budget:
                        break
            if len(tavily_candidates) < tavily_candidate_budget:
                for priority in sorted(by_query, reverse=True):
                    tavily_candidates.extend(by_query[priority][:tavily_candidate_budget - len(tavily_candidates)])
                    if len(tavily_candidates) == tavily_candidate_budget:
                        break
        logger.info(
            "AI_RECOMMENDATION_TAVILY_SELECTION candidate_pool_count=%d selected_count=%d "
            "distinct_query_priority_count=%d",
            sum(classification_by_id[place.kakao_place_id].status == CategoryMatchStatus.CONFIRMED
                for place in candidate_by_id.values()),
            len(tavily_candidates), len({candidate_query_priority.get(place.kakao_place_id, 0)
                                         for place in tavily_candidates}),
        )
        if diagnostics.enabled():
            # Development-only: shows whether each candidate was retrieved by a
            # specific record term or only by a broad place-type query.
            selected_ids = {place.kakao_place_id for place in tavily_candidates}
            for place_id, place in candidate_by_id.items():
                linked_terms = list(dict.fromkeys(
                    facet.target_text for _, facet in query_facets_by_id.get(place_id, [])
                ))
                logger.info(
                    "AI_RECOMMENDATION_CANDIDATE_LINK_DEBUG kakao_place_id=%s place_name=%r "
                    "categories=%s category_status=%s kakao_queries=%r query_priority=%d "
                    "linked_terms=%r category_facet_count=%d tavily_selected=%d",
                    place_id, place.place_name,
                    ",".join(value.value for value in classification_by_id[place_id].categories),
                    classification_by_id[place_id].status.value,
                    candidate_queries.get(place_id, []), candidate_query_priority.get(place_id, 0),
                    linked_terms, len(candidate_facets_by_id.get(place_id, [])),
                    int(place_id in selected_ids),
                )
        diagnostics.add_count("tavily_targets", len(tavily_candidates))
        for place in tavily_candidates:
            diagnostics.count_unique("tavily_unique_targets", place.kakao_place_id)
        evidence_by_id: dict[str, tuple[list[PreferenceEvidence], FeatureEvidenceStatus]] = {}
        tavily_started_at = time.perf_counter()
        if relevant_facets and tavily_candidates:
            cached_candidate_ids = {
                place.kakao_place_id for place in tavily_candidates
                if self._cache_get(self._tavily_key_for(place, region, query_facets_by_id[place.kakao_place_id])) is not None
            }
            external_keys = {
                place.kakao_place_id for place in tavily_candidates
                if self.tavily_api_key and self._cache_get(self._tavily_key_for(
                    place, region, query_facets_by_id[place.kakao_place_id])) is None
            }
            tavily_cache_hits = len(cached_candidate_ids)
            external_places = [place for place in tavily_candidates
                               if place.kakao_place_id in external_keys][:tavily_call_budget]
            allowed_ids = cached_candidate_ids | {place.kakao_place_id for place in external_places}
            verify_places = [place for place in tavily_candidates if place.kakao_place_id in allowed_ids]
            tavily_calls = len(external_places)
            diagnostics.add_count("tavily_result_cache_hits", tavily_cache_hits)
            diagnostics.add_count("tavily_calls", tavily_calls)
            diagnostics.add_count("tavily_external_candidate_calls", tavily_calls)
            if len(external_keys) > tavily_calls:
                diagnostics.set_flag("tavily_call_budget_exhausted")
                tavily_skip_reason = "tavily_call_budget_exhausted"
            if not self.tavily_api_key and len(cached_candidate_ids) < len(tavily_candidates):
                tavily_skip_reason = "missing_tavily_configuration"
            elif not external_keys:
                tavily_skip_reason = "tavily_result_cache_hit"
            with ThreadPoolExecutor(max_workers=max(1, min(3, len(verify_places)))) as executor:
                futures = {}
                for place in verify_places:
                    context = contextvars.copy_context()
                    future = executor.submit(
                        context.run, self._tavily_for_place, place, region,
                        candidate_facets_by_id[place.kakao_place_id],
                        query_facets_by_id[place.kakao_place_id],
                    )
                    futures[future] = place.kakao_place_id
                for future, place_id in ((future, place_id) for future, place_id in futures.items()):
                    try:
                        rows, status = future.result()
                        evidence_by_id[place_id] = rows, status
                    except Exception as exc:
                        logger.info("place feature evidence failed reason=%s", type(exc).__name__)
                        tavily_had_error = True
                        diagnostics.error("tavily", type(exc).__name__)
                        if isinstance(exc, httpx.TimeoutException):
                            diagnostics.set_flag("tavily_timeout")
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
        diagnostics.set_value("tavily_skip_reason", tavily_skip_reason or "none")
        diagnostics.stage("tavily_provider", int((time.perf_counter() - tavily_started_at) * 1000))

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

        logger.info("place candidate search complete category=%s kakao_calls=%d tavily_calls=%d candidates=%d elapsed_ms=%d",
                    category.value, kakao_calls, tavily_calls, len(enriched),
                    int((time.perf_counter() - started_at) * 1000))
        evidence_confirmed_count = sum(
            row.status == FeatureEvidenceStatus.CONFIRMED
            for item in enriched for row in item.preference_evidence
        )
        identity_unverified_count = sum(
            row.status == FeatureEvidenceStatus.PLACE_IDENTITY_UNVERIFIED
            for item in enriched for row in item.preference_evidence
        )
        diagnostics.add_count("tavily_identity_unverified", identity_unverified_count)
        diagnostics.add_count("tavily_feature_evidence_confirmed", evidence_confirmed_count)
        diagnostics.add_count("tavily_feature_evidence_insufficient", sum(
            row.status == FeatureEvidenceStatus.INSUFFICIENT
            for item in enriched for row in item.preference_evidence
        ))
        diagnostics.add_count("category_confirmed_candidates", sum(
            item.classification.status == CategoryMatchStatus.CONFIRMED for item in enriched
        ))
        diagnostics.add_count("category_unconfirmed_candidates", sum(
            item.classification.status != CategoryMatchStatus.CONFIRMED for item in enriched
        ))
        for item in enriched:
            status_name = item.feature_search_status.value
            diagnostics.add_count(f"tavily_status_{status_name}")
            if status_name in {FeatureEvidenceStatus.CONFIRMED.value, FeatureEvidenceStatus.INSUFFICIENT.value,
                               FeatureEvidenceStatus.PLACE_IDENTITY_UNVERIFIED.value}:
                diagnostics.add_count("tavily_identity_checked")
            if status_name in {FeatureEvidenceStatus.CONFIRMED.value, FeatureEvidenceStatus.INSUFFICIENT.value}:
                diagnostics.add_count("tavily_identity_verified")
            if status_name == FeatureEvidenceStatus.PLACE_IDENTITY_UNVERIFIED.value:
                diagnostics.add_count("tavily_identity_failed")
            diagnostics.decision("tavily_verification", item.place.kakao_place_id,
                                 "accepted" if status_name == FeatureEvidenceStatus.CONFIRMED.value else "not_confirmed",
                                 status_name)
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
            "category_mismatch_count=%d region_mismatch_count=%d region_scope_level=%s "
            "region_alias_normalized=%s kakao_raw_candidate_count=%d visited_excluded_count=%d "
            "duplicate_excluded_count=%d region_search_stage_count=%d "
            "search_skip_reason=%s kakao_status=%s",
            category.value, len(queries), kakao_calls, kakao_cache_hits, kakao_empty_cache_hits,
            len(enriched), category_mismatch_count, region_mismatch_count,
            "district" if len(region_parts) > 1 else "city_or_province",
            bool(region_parts and search_region.split()[0] != region_parts[0]),
            kakao_raw_candidate_count, visited_excluded_count,
            duplicate_excluded_count, len(set(query_regions)),
            skip_reason or "none", kakao_status.value,
        )
        category_verified_count = sum(
            item.classification.status == CategoryMatchStatus.CONFIRMED for item in enriched
        )
        category_rejected_count = category_mismatch_count + sum(
            item.classification.status != CategoryMatchStatus.CONFIRMED for item in enriched
        )
        logger.info(
            "AI_RECOMMENDATION_DIAGNOSTIC event=kakao_category_filter pipeline=category-v5 category=%s "
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
            query_count=min(len(queries), kakao_call_budget),
            search_skip_reason=skip_reason,
            kakao_cache_hit_count=kakao_cache_hits,
            kakao_empty_cache_hit_count=kakao_empty_cache_hits,
        )
