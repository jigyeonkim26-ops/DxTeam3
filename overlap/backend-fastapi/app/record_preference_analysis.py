"""Evidence-grounded analysis and bounded offline fallback for record preferences.

The category-v3 recommendation API consumes this module. Optional trusted
place-category metadata can be supplied without a database schema change.
"""

from __future__ import annotations

import json
import logging
import re
from collections import Counter
from enum import Enum
from typing import Any, Callable

import httpx
from pydantic import BaseModel, ConfigDict, Field, ValidationError

from .config import OPENROUTER_API_KEY, OPENROUTER_MODEL
from .recommendation_record_adapter import RecommendationEmotionCode, RecommendationRecord

logger = logging.getLogger("uvicorn.error")


class RecommendationCategory(str, Enum):
    ALL = "all"
    FOOD = "food"
    BAR = "bar"
    CAFE = "cafe"
    NATURE = "nature"
    ACTIVITY = "activity"


class PlaceType(str, Enum):
    FOOD = "food"
    BAR = "bar"
    CAFE = "cafe"
    NATURE = "nature"
    ACTIVITY = "activity"
    UNKNOWN = "unknown"


class EvidenceStatus(str, Enum):
    VERIFIED = "verified"
    PARTIAL = "partial"
    UNKNOWN = "unknown"
    UNAVAILABLE = "unavailable"


class FacetTargetKind(str, Enum):
    MENU = "menu"
    DRINK = "drink"
    FOOD = "food"
    AMBIENCE = "ambience"
    SPACE = "space"
    ACTIVITY = "activity"
    SCENERY = "scenery"
    SERVICE = "service"
    FACILITY = "facility"
    OTHER = "other"


class PreferenceFacet(BaseModel):
    """One target-feature relation tied to a source quote."""

    model_config = ConfigDict(extra="forbid")

    target_kind: FacetTargetKind
    # The target label must be copied from the record, never invented.
    target_text: str = Field(min_length=1, max_length=80)
    features: list[str] = Field(default_factory=list, max_length=8)
    categories: list[RecommendationCategory] = Field(default_factory=list, max_length=6)
    polarity: str = Field(pattern="^(liked|disliked|neutral)$")
    evidence: str = Field(min_length=1, max_length=240)
    confidence: float = Field(ge=0, le=1)


class RecordPreferenceAnalysis(BaseModel):
    model_config = ConfigDict(extra="forbid")

    record_id: int
    place_name: str | None = None
    place_type: PlaceType = PlaceType.UNKNOWN
    place_type_label: str | None = Field(default=None, max_length=80)
    place_type_evidence: str | None = Field(default=None, max_length=240)
    categories: list[RecommendationCategory] = Field(default_factory=list, max_length=6)
    emotion: RecommendationEmotionCode
    emotion_intensity: float = Field(ge=0, le=1)
    facets: list[PreferenceFacet] = Field(default_factory=list, max_length=12)
    evidence_status: EvidenceStatus = EvidenceStatus.UNKNOWN


class RecordPreferenceAnalysisResponse(BaseModel):
    analyses: list[RecordPreferenceAnalysis] = Field(default_factory=list, max_length=30)


class RecordPlaceMetadata(BaseModel):
    """Optional trusted place metadata supplied by a caller, e.g. Kakao Local."""

    kakao_category: str | None = Field(default=None, max_length=160)
    place_type: PlaceType | None = None
    place_type_label: str | None = Field(default=None, max_length=80)


_MAX_RECORDS = 30
_MAX_CONTENT_CHARS = 500
_PHONE = re.compile(r"(?<!\d)(?:\+?\d[\d\s().-]{7,}\d)(?!\d)")
_EMAIL = re.compile(r"\b[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}\b")
_URL = re.compile(r"https?://\S+", re.IGNORECASE)
_SPACE = re.compile(r"\s+")
_SAFE_PROVIDER_CODE = re.compile(r"^[A-Za-z0-9_.:-]{1,80}$")
_SAFE_PROVIDER_PARAM = re.compile(r"^[A-Za-z0-9_.\[\]-]{1,180}$")
_SAFE_SCHEMA_KEYWORDS = frozenset({
    "response_format", "json_schema", "schema", "type", "properties", "required",
    "additionalProperties", "enum", "items", "maxItems", "minItems", "maxLength",
    "minLength", "minimum", "maximum", "strict", "provider", "require_parameters",
    "messages", "model", "temperature", "max_tokens", "stream",
})
_SAFE_PROVIDER_PARAM_COMPONENTS = frozenset({
    "response_format", "json_schema", "schema", "properties", "facets", "items",
    "features", "categories", "records", "place_type", "place_type_label",
    "place_type_evidence", "target_kind", "target_text", "polarity", "evidence",
    "confidence", "provider", "require_parameters", "messages", "model",
    "temperature", "max_tokens", "stream",
})

# Local names are treated as a hint only. Ambiguous terms such as "마켓" and
# "라운지" deliberately remain unknown and can be resolved by structured LLM.
_PLACE_NAME_RULES: tuple[tuple[PlaceType, tuple[str, ...]], ...] = (
    (PlaceType.BAR, ("이자카야", "술집", "호프", "펍", "포차", "바 ")),
    (PlaceType.CAFE, ("카페", "커피숍", "커피전문점")),
    (PlaceType.NATURE, ("공원", "산책로", "수목원", "전망대", "산 ", "호수")),
    (PlaceType.ACTIVITY, ("야구장", "경기장", "농구장", "축구장", "공연장", "미술관", "박물관")),
    (PlaceType.FOOD, ("음식점", "식당", "레스토랑", "치킨", "초밥", "국밥", "고깃집")),
)

_KAKAO_CATEGORY_RULES: tuple[tuple[PlaceType, tuple[str, ...]], ...] = (
    (PlaceType.BAR, ("술집", "이자카야", "호프", "주점", "바")),
    (PlaceType.CAFE, ("카페", "커피전문점")),
    (PlaceType.NATURE, ("공원", "자연명소", "산책로", "수목원", "관광명소")),
    (PlaceType.ACTIVITY, ("스포츠", "야구장", "경기장", "공연", "전시", "문화시설")),
    (PlaceType.FOOD, ("음식점", "한식", "양식", "일식", "중식", "분식")),
)

_EMOTION_STRENGTH = {
    RecommendationEmotionCode.LOVE: 1.0,
    RecommendationEmotionCode.LIKE: 0.8,
    RecommendationEmotionCode.GOOD: 0.6,
    RecommendationEmotionCode.NEUTRAL: 0.35,
    RecommendationEmotionCode.DISAPPOINTED: 0.2,
    RecommendationEmotionCode.BAD: 0.0,
}
_POSITIVE = {
    RecommendationEmotionCode.LOVE,
    RecommendationEmotionCode.LIKE,
    RecommendationEmotionCode.GOOD,
}

# Offline fallback recognizes only literal, domain-bearing terms. Generic
# attributes stay unclassified unless a record/place type supplies context.
_FALLBACK_TERMS = (
    ("\uD0C0\uCF54\uC57C\uB07C", FacetTargetKind.FOOD, RecommendationCategory.FOOD),
    ("\uB099\uC9C0\uBCF6\uC74C", FacetTargetKind.FOOD, RecommendationCategory.FOOD),
    ("\uC2A4\uD0A4\uC57C\uD0A4", FacetTargetKind.FOOD, RecommendationCategory.FOOD),
    ("\uD56D\uC815\uC0B4", FacetTargetKind.FOOD, RecommendationCategory.FOOD),
    ("\uD31D\uC774\uBC84\uC12F", FacetTargetKind.FOOD, RecommendationCategory.FOOD),
    ("\uB864\uCF00\uC774\uD06C", FacetTargetKind.FOOD, RecommendationCategory.CAFE),
    ("\uBE60\uC5D0\uC57C", FacetTargetKind.FOOD, RecommendationCategory.FOOD),
    ("\uBD09\uACE8\uB808", FacetTargetKind.FOOD, RecommendationCategory.FOOD),
    ("\uAC10\uBC14\uC2A4", FacetTargetKind.FOOD, RecommendationCategory.FOOD),
    ("\uB0C9\uC0BC", FacetTargetKind.FOOD, RecommendationCategory.FOOD),
    ("\uB9C9\uCC3D", FacetTargetKind.FOOD, RecommendationCategory.FOOD),
    ("\uAD00\uC790", FacetTargetKind.FOOD, RecommendationCategory.FOOD),
    ("\uB2ED\uAF2C\uCE58", FacetTargetKind.FOOD, RecommendationCategory.FOOD),
    ("\uC57C\uAD6C\uACBD\uAE30", FacetTargetKind.ACTIVITY, RecommendationCategory.ACTIVITY),
    ("\uD648\uAC1C\uB9C9\uC804", FacetTargetKind.ACTIVITY, RecommendationCategory.ACTIVITY),
    ("\uC774\uBCA4\uD2B8", FacetTargetKind.ACTIVITY, RecommendationCategory.ACTIVITY),
    ("\uBC14\uC0AD", FacetTargetKind.OTHER, None),
    ("\uCD09\uCD09", FacetTargetKind.OTHER, None),
    ("유자하이볼", FacetTargetKind.DRINK, RecommendationCategory.BAR),
    ("과일하이볼", FacetTargetKind.DRINK, RecommendationCategory.BAR),
    ("하이볼", FacetTargetKind.DRINK, RecommendationCategory.BAR),
    ("칵테일", FacetTargetKind.DRINK, RecommendationCategory.BAR),
    ("꼬치", FacetTargetKind.FOOD, RecommendationCategory.FOOD),
    ("치킨", FacetTargetKind.FOOD, RecommendationCategory.FOOD),
    ("초밥", FacetTargetKind.FOOD, RecommendationCategory.FOOD),
    ("파스타", FacetTargetKind.FOOD, RecommendationCategory.FOOD),
    ("피자", FacetTargetKind.FOOD, RecommendationCategory.FOOD),
    ("커피", FacetTargetKind.DRINK, RecommendationCategory.CAFE),
    ("케이크", FacetTargetKind.FOOD, RecommendationCategory.CAFE),
    ("풍경", FacetTargetKind.SCENERY, RecommendationCategory.NATURE),
    ("노을", FacetTargetKind.SCENERY, RecommendationCategory.NATURE),
    ("산책", FacetTargetKind.SCENERY, RecommendationCategory.NATURE),
    ("공원", FacetTargetKind.SCENERY, RecommendationCategory.NATURE),
    ("무등산", FacetTargetKind.SCENERY, RecommendationCategory.NATURE),
    ("자연", FacetTargetKind.SCENERY, RecommendationCategory.NATURE),
    ("숲", FacetTargetKind.SCENERY, RecommendationCategory.NATURE),
    ("야구", FacetTargetKind.ACTIVITY, RecommendationCategory.ACTIVITY),
    ("농구", FacetTargetKind.ACTIVITY, RecommendationCategory.ACTIVITY),
    ("응원", FacetTargetKind.ACTIVITY, RecommendationCategory.ACTIVITY),
    ("공연", FacetTargetKind.ACTIVITY, RecommendationCategory.ACTIVITY),
    ("전시", FacetTargetKind.ACTIVITY, RecommendationCategory.ACTIVITY),
    ("조용", FacetTargetKind.AMBIENCE, None),
    ("넓", FacetTargetKind.SPACE, None),
    ("아늑", FacetTargetKind.AMBIENCE, None),
)


def _norm(value: str | None) -> str:
    return _SPACE.sub(" ", (value or "").casefold()).strip()


def _redact_and_limit(value: str) -> str:
    """Remove common direct identifiers and cap text before external transfer."""
    value = _URL.sub("[URL]", value)
    value = _EMAIL.sub("[EMAIL]", value)
    value = _PHONE.sub("[PHONE]", value)
    return _SPACE.sub(" ", value).strip()[:_MAX_CONTENT_CHARS]


def _metadata_type(metadata: RecordPlaceMetadata | None) -> tuple[PlaceType, str | None, str | None]:
    if metadata is None:
        return PlaceType.UNKNOWN, None, None
    if metadata.place_type and metadata.place_type != PlaceType.UNKNOWN:
        return metadata.place_type, metadata.place_type_label or metadata.place_type.value, "trusted_place_metadata"
    category = metadata.kakao_category or ""
    for place_type, terms in _KAKAO_CATEGORY_RULES:
        if any(term in category for term in terms):
            return place_type, metadata.place_type_label or category[:80], "kakao_category"
    return PlaceType.UNKNOWN, None, None


def _name_type(place_name: str | None) -> tuple[PlaceType, str | None, str | None]:
    name = _norm(place_name)
    for place_type, terms in _PLACE_NAME_RULES:
        for term in terms:
            normalized_term = _norm(term)
            # Venue labels are useful only as explicit whole-name or suffix
            # evidence. Short interior fragments (e.g. "산" in "산등무") are
            # too ambiguous to establish a place type.
            tokens = set(name.split())
            if ((len(normalized_term) >= 2 and normalized_term in tokens)
                    or (normalized_term == "\uC0B0" and name.endswith(normalized_term))
                    or (len(normalized_term) >= 2 and name.endswith(normalized_term))):
                return place_type, place_name, "place_name_hint"
    return PlaceType.UNKNOWN, None, None


_RECORD_CONTEXT_TYPE_RULES: tuple[tuple[PlaceType, tuple[str, ...]], ...] = (
    (PlaceType.BAR, ("\uC774\uC790\uCE74\uC57C", "\uC220\uC9D1", "\uD3EC\uCC28", "\uD3EC\uC7A5\uB9C8\uCC28", "\uD638\uD504\uC9D1", "\uC8FC\uC810")),
    (PlaceType.CAFE, ("\uCE74\uD398", "\uCEE4\uD53C\uC804\uBB38\uC810", "\uCEE4\uD53C\uC20D")),
    (PlaceType.NATURE, ("\uACF5\uC6D0", "\uC0B0\uCC45\uB85C", "\uB4F1\uC0B0\uB85C", "\uC790\uC5F0\uBA85\uC18C", "\uC218\uBAA9\uC6D0", "\uD574\uBCC0", "\uC232\uAE38")),
    (PlaceType.ACTIVITY, ("\uC57C\uAD6C\uC7A5", "\uB18D\uAD6C\uC7A5", "\uACBD\uAE30\uC7A5", "\uC2A4\uD3EC\uCE20\uC13C\uD130", "\uC804\uC2DC\uC7A5", "\uACF5\uC5F0\uC7A5", "\uBB38\uD654\uC2DC\uC124", "\uBB3C\uAD00", "\uBBF8\uC220\uAD00")),
    (PlaceType.FOOD, ("\uC74C\uC2DD\uC810", "\uC2DD\uB2F9", "\uB808\uC2A4\uD1A0\uB791", "\uD55C\uC2DD\uB2F9", "\uCE58\uD0A8\uC9D1", "\uACE0\uAE43\uC9D1", "\uD68C\uC9D1")),
)


def _record_type_hint(record: RecommendationRecord,
                      metadata: RecordPlaceMetadata | None) -> tuple[PlaceType, str | None, str | None]:
    """Prefer trusted metadata, then explicit record wording and unambiguous name hints."""
    place_type, label, evidence = _metadata_type(metadata)
    if place_type != PlaceType.UNKNOWN:
        return place_type, label, evidence
    source = _norm(record.content)
    for place_type, terms in _RECORD_CONTEXT_TYPE_RULES:
        term = next((term for term in terms if _norm(term) in source), None)
        if term:
            return place_type, term, "record_context_hint"
    return _name_type(record.place_name)


_EXPLICIT_NEGATIVE_SPANS = (
    "\uB108\uBB34 \uB9E4\uC6E0", "\uB9CE\uC774 \uB9E4\uC6E0", "\uB9E4\uC6CC\uC11C \uC544\uC26C",
    "\uC544\uC26C", "\uD488\uC808", "\uBCC4\uB85C", "\uC2EB\uC5B4", "\uBD88\uD3B8",
    "\uBD88\uCE5C\uC808", "\uC2E4\uB9DD", "\uC9DC\uC99D", "\uBABB \uC54C\uC544\uB4E4",
    "\uC798 \uC54C\uC544\uB4E3\uC9C0 \uBABB", "\uB290\uB838", "\uB108\uBB34 \uC624\uB798",
)


def _has_explicit_negative_span(value: str | None) -> bool:
    normalized = _norm(value)
    return any(_norm(marker) in normalized for marker in _EXPLICIT_NEGATIVE_SPANS)


class _AnalysisResponseFailure(ValueError):
    """A safe, stage-tagged failure while interpreting a provider response."""

    def __init__(self, stage: str, reason: str) -> None:
        super().__init__(reason)
        self.stage = stage
        self.reason = reason


def _parse_json(content: Any) -> Any:
    if not isinstance(content, str):
        raise _AnalysisResponseFailure("json_parse", "content_not_text")
    text = content.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[-1].rsplit("```", 1)[0].strip()
    start = text.find("{")
    if start < 0:
        raise _AnalysisResponseFailure("json_parse", "object_not_found")
    try:
        parsed, _ = json.JSONDecoder().raw_decode(text[start:])
    except json.JSONDecodeError as exc:
        remainder = text[start:].rstrip()
        reason = "truncated_json" if exc.pos >= max(0, len(text[start:]) - 1) or not remainder.endswith(("}", "]")) else "malformed_json"
        raise _AnalysisResponseFailure("json_parse", reason) from None
    return parsed


class RecordPreferenceAnalysisService:
    """Build record-scoped preference facets without changing recommendation results."""

    API_URL = "https://openrouter.ai/api/v1/chat/completions"
    _SCHEMA = {
        "name": "record_preference_analysis",
        "strict": True,
        "schema": {
            "type": "object",
            "properties": {"records": {"type": "array", "maxItems": _MAX_RECORDS, "items": {
                "type": "object", "properties": {
                    "record_id": {"type": "integer"},
                    "place_type": {"type": "string", "enum": [item.value for item in PlaceType]},
                    "place_type_label": {"type": ["string", "null"]},
                    "place_type_evidence": {"type": ["string", "null"]},
                    "categories": {"type": "array", "items": {"type": "string", "enum": [item.value for item in RecommendationCategory]}},
                    "facets": {"type": "array", "maxItems": 12, "items": {
                        "type": "object", "properties": {
                            "target_kind": {"type": "string", "enum": [item.value for item in FacetTargetKind]},
                            "target_text": {"type": "string"},
                            "features": {"type": "array", "maxItems": 8, "items": {"type": "string"}},
                            "categories": {"type": "array", "items": {"type": "string", "enum": [item.value for item in RecommendationCategory]}},
                            "polarity": {"type": "string", "enum": ["liked", "disliked", "neutral"]},
                            "evidence": {"type": "string"},
                            "confidence": {"type": "number", "minimum": 0, "maximum": 1},
                        }, "required": ["target_kind", "target_text", "features", "categories", "polarity", "evidence", "confidence"], "additionalProperties": False,
                    }},
                }, "required": ["record_id", "place_type", "place_type_label", "place_type_evidence", "categories", "facets"], "additionalProperties": False,
            }}}, "required": ["records"], "additionalProperties": False,
        },
    }

    @staticmethod
    def _safe_provider_diagnostics(error_object: Any) -> tuple[str, str]:
        """Extract only allowlisted schema fields/keywords; never log provider prose."""
        if not isinstance(error_object, dict):
            return "unavailable", "unavailable"
        raw_param = error_object.get("param")
        param = str(raw_param)[:180] if isinstance(raw_param, (str, int)) else ""
        components = re.split(r"[.\[\]]+", param) if param else []
        if (not param or not _SAFE_PROVIDER_PARAM.fullmatch(param)
                or any(component and component not in _SAFE_PROVIDER_PARAM_COMPONENTS
                       and not component.isdigit() for component in components)):
            param = "unavailable"
        raw_message = error_object.get("message")
        message = raw_message if isinstance(raw_message, str) else ""
        # Provider messages can contain prompts or user data. Return only a
        # matching JSON Schema keyword from a fixed allowlist, never the text.
        keyword = next((value for value in sorted(_SAFE_SCHEMA_KEYWORDS, key=len, reverse=True)
                        if re.search(rf"(?<![A-Za-z0-9_]){re.escape(value)}(?![A-Za-z0-9_])", message)), None)
        return param, keyword or "unavailable"

    def __init__(self, api_key: str | None = None, model: str | None = None,
                 post_json: Callable[..., Any] | None = None, *, max_records: int = _MAX_RECORDS,
                 max_content_chars: int = _MAX_CONTENT_CHARS) -> None:
        self.api_key = OPENROUTER_API_KEY if api_key is None else api_key.strip()
        self.model = OPENROUTER_MODEL if model is None else model.strip()
        self._post_json = post_json or httpx.post
        self.max_records = max(1, min(max_records, _MAX_RECORDS))
        self.max_content_chars = max(80, min(max_content_chars, _MAX_CONTENT_CHARS))

    @staticmethod
    def _max_output_tokens(record_count: int) -> int:
        # A full preference object with several facets needs more than the old
        # 140 tokens per record. Keep the 2-record verified test budget while
        # scaling for mixed-history batches without unbounded output cost.
        return min(12000, max(1200, 600 * record_count))

    def analyze(
        self,
        records: list[RecommendationRecord],
        *,
        place_metadata: dict[int, RecordPlaceMetadata] | None = None,
        category: RecommendationCategory | str = RecommendationCategory.ALL,
    ) -> RecordPreferenceAnalysisResponse:
        """Analyze a bounded set of records and optionally scope results to a category."""
        category = RecommendationCategory(category)
        metadata = place_metadata or {}
        selected = records[:self.max_records]
        base = [self._base_analysis(record, metadata.get(record.record_id)) for record in selected]
        if not selected:
            return RecordPreferenceAnalysisResponse()
        if not self.api_key or not self.model:
            logger.info("record preference analysis unavailable source=local_fallback stage=configuration "
                        "reason=missing_configuration records=%d", len(selected))
            unavailable = [item.model_copy(update={"evidence_status": EvidenceStatus.UNAVAILABLE}) for item in base]
            return self._filter_category(RecordPreferenceAnalysisResponse(analyses=unavailable), category)

        allowed_ids = {record.record_id for record in selected}
        record_inputs = [{
            "record_id": record.record_id,
            "place_name": _redact_and_limit(record.place_name or "")[:120],
            "place_type_hint": item.place_type.value,
            "trusted_category": _redact_and_limit((metadata.get(record.record_id).kakao_category or "") if metadata.get(record.record_id) else "")[:120],
            "emotion": record.emotion_code.value,
            "content": _redact_and_limit(record.content)[:self.max_content_chars],
        } for record, item in zip(selected, base)]
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": (
                    "Analyze each memory independently. Return one JSON object with a top-level records array. "
                    "Each record object must contain record_id, place_type, place_type_label, place_type_evidence, categories, and facets. "
                    "Each facet object must contain target_kind, target_text, features, categories, polarity, evidence, and confidence. "
                    "Use place_type from food, bar, cafe, nature, activity, unknown; categories from all, food, bar, cafe, nature, activity; "
                    "target_kind from menu, drink, food, ambience, space, activity, scenery, service, facility, other; "
                    "polarity from liked, disliked, neutral. Use null for an unknown place type label or evidence. "
                    "Extract multiple positive or negative target-feature relations when explicit. "
                    "target_text must be a literal short span from place_name or content; features must be explicit terms from content. "
                    "Copy feature wording exactly from the record, preserving Korean endings and inflections; do not paraphrase or normalize it "
                    "(for example, keep '조용해서' as '조용해서', not '조용한'). Emit each distinct stated feature rather than dropping it. "
                    "A positive overall emotion can contain both liked and disliked details. Split them into separate facets: "
                    "for example, in '낙지볶음은 맛있었지만 너무 매웠다', keep the dish/taste praise liked and mark the explicitly excessive spiciness disliked. "
                    "Never mark a feature liked when its own literal wording is explicitly negative. Do not treat 'spicy' as a liked preference from that example. "
                    "evidence must be an exact short quote from input place_name or content. Never infer a target (e.g. parking) from a generic feature (e.g. spacious). "
                    "Use trusted_category/place_type_hint first. Otherwise infer place type only when evidence is explicit; use unknown if uncertain. "
                    "Use category all plus relevant specific categories. Do not transfer a preference between unrelated place types. "
                    "For negative emotions, only mark explicit dislikes and do not turn them into liked preferences. Do not invent facts."
                )},
                {"role": "user", "content": json.dumps({"records": record_inputs}, ensure_ascii=False)},
            ],
            "response_format": {"type": "json_object"},
            "provider": {"require_parameters": True},
            "temperature": 0,
            "max_tokens": self._max_output_tokens(len(selected)),
            "stream": False,
        }
        stage = "http_response"
        finish_reason = "unavailable"
        http_status = "none"
        try:
            response = self._post_json(self.API_URL, headers={
                "Authorization": f"Bearer {self.api_key}", "Content-Type": "application/json",
            }, json=payload, timeout=35.0)
            http_status = getattr(response, "status_code", 200)
            response.raise_for_status()
            stage = "response_extraction"
            try:
                response_body = response.json()
            except (ValueError, TypeError):
                raise _AnalysisResponseFailure(stage, "response_body_not_json") from None
            if not isinstance(response_body, dict):
                raise _AnalysisResponseFailure(stage, "response_body_not_object")
            choices = response_body.get("choices")
            if not isinstance(choices, list) or not choices:
                raise _AnalysisResponseFailure(stage, "choices_missing_or_empty")
            choice = choices[0]
            if not isinstance(choice, dict):
                raise _AnalysisResponseFailure(stage, "choice_not_object")
            message = choice.get("message")
            if not isinstance(message, dict):
                raise _AnalysisResponseFailure(stage, "message_missing_or_invalid")
            content = message.get("content")
            if not isinstance(content, str):
                raise _AnalysisResponseFailure(stage, "content_missing_or_not_text")

            stage = "finish_reason"
            raw_finish_reason = choice.get("finish_reason")
            finish_reason = raw_finish_reason if raw_finish_reason in {
                "stop", "length", "content_filter", "tool_calls", "function_call"
            } else "unavailable"
            if finish_reason == "length":
                raise _AnalysisResponseFailure(stage, "token_limit")
            if finish_reason == "content_filter":
                raise _AnalysisResponseFailure(stage, "content_filtered")

            stage = "json_parse"
            raw = _parse_json(content)
            if not isinstance(raw, dict):
                raise _AnalysisResponseFailure("records_validation", "root_not_object")
            if "records" not in raw:
                raise _AnalysisResponseFailure("records_validation", "records_field_missing")
            if not isinstance(raw["records"], list):
                raise _AnalysisResponseFailure("records_validation", "records_not_array")
            if not raw["records"]:
                raise _AnalysisResponseFailure("records_validation", "records_empty")

            parsed_by_id = {}
            base_by_id = {item.record_id: item for item in base}
            source_by_id = {record.record_id: record for record in selected}
            required_fields = {"record_id", "place_type", "place_type_label", "place_type_evidence", "categories", "facets"}
            records_array_count = len(raw["records"])
            required_fields_validated_count = 0
            pydantic_validated_count = 0
            evidence_accepted_facet_count = 0
            record_failures = {
                "item_not_object": 0,
                "record_id_invalid_or_unexpected": 0,
                "duplicate_record_id": 0,
                "required_fields_missing": 0,
                "pydantic_validation_error": 0,
            }
            pydantic_error_types: Counter[str] = Counter()
            missing_required_names: Counter[str] = Counter()
            evidence_rejected_facets = 0
            evidence_failure_counts: Counter[str] = Counter()
            stage = "record_validation"
            for raw_item in raw["records"]:
                if not isinstance(raw_item, dict):
                    record_failures["item_not_object"] += 1
                    continue
                record_id = raw_item.get("record_id")
                if not isinstance(record_id, int) or isinstance(record_id, bool) or record_id not in allowed_ids:
                    record_failures["record_id_invalid_or_unexpected"] += 1
                    continue
                if record_id in parsed_by_id:
                    record_failures["duplicate_record_id"] += 1
                    continue
                if not required_fields.issubset(raw_item):
                    record_failures["required_fields_missing"] += 1
                    for missing_name in required_fields.difference(raw_item):
                        missing_required_names[missing_name] += 1
                    continue
                required_fields_validated_count += 1
                # Emotion, strength, and source place name are deterministic input
                # facts, not fields the model is allowed to rewrite.
                item_data = base_by_id[record_id].model_dump()
                for field in ("place_type", "place_type_label", "place_type_evidence", "categories", "facets"):
                    if field in raw_item:
                        item_data[field] = raw_item[field]
                try:
                    item = RecordPreferenceAnalysis.model_validate(item_data)
                except ValidationError as exc:
                    record_failures["pydantic_validation_error"] += 1
                    # Pydantic error types are fixed identifiers. Never log its
                    # message, input value, or context because they can contain
                    # provider generated text.
                    for validation_error in exc.errors(include_input=False, include_context=False):
                        error_type = validation_error.get("type")
                        if isinstance(error_type, str) and re.fullmatch(r"[A-Za-z0-9_.-]{1,60}", error_type):
                            pydantic_error_types[error_type] += 1
                    continue
                pydantic_validated_count += 1
                source = source_by_id[record_id]
                raw_facet_count = len(item.facets)
                item = self._validate_evidence(
                    item, source, metadata.get(source.record_id), diagnostics=evidence_failure_counts,
                )
                evidence_rejected_facets += raw_facet_count - len(item.facets)
                evidence_accepted_facet_count += len(item.facets)
                parsed_by_id[item.record_id] = item

            recovered_place_types = evidence_failure_counts.pop("place_type_recovered_from_record_context", 0)
            recovered_facet_domains = evidence_failure_counts.pop("facet_domain_recovered_from_literal_term", 0)
            if recovered_place_types or recovered_facet_domains:
                logger.info(
                    "record preference analysis category_recovery record_context_type_count=%d "
                    "literal_facet_domain_count=%d",
                    recovered_place_types, recovered_facet_domains,
                )

            if not parsed_by_id:
                failure_summary = ",".join(
                    f"{name}:{count}" for name, count in record_failures.items() if count
                ) or "none"
                missing_summary = ",".join(
                    f"{name}:{count}" for name, count in sorted(missing_required_names.items())
                ) or "none"
                pydantic_summary = ",".join(
                    f"{name}:{count}" for name, count in sorted(pydantic_error_types.items())
                ) or "none"
                logger.info(
                    "record preference analysis degraded stage=record_validation reason=no_valid_records "
                    "record_failure_counts=%s missing_required_fields=%s pydantic_error_types=%s",
                    failure_summary, missing_summary, pydantic_summary,
                )
                raise _AnalysisResponseFailure("record_validation", "no_valid_records")
            if evidence_failure_counts:
                evidence_summary = ",".join(
                    f"{name}:{count}" for name, count in sorted(evidence_failure_counts.items())
                )
                logger.info(
                    "record preference analysis degraded stage=evidence_validation "
                    "reason=source_evidence_rejected failure_counts=%s",
                    evidence_summary,
                )
            analyses = []
            for record, fallback in zip(selected, base):
                analyzed = parsed_by_id.get(record.record_id)
                analyses.append(analyzed if analyzed is not None else fallback.model_copy(
                    update={"evidence_status": EvidenceStatus.UNAVAILABLE}
                ))
            fallback_count = len(selected) - len(parsed_by_id)
            if any(record_failures.values()) or fallback_count or evidence_rejected_facets:
                failure_summary = ",".join(
                    f"{name}:{count}" for name, count in record_failures.items() if count
                ) or "none"
                missing_summary = ",".join(
                    f"{name}:{count}" for name, count in sorted(missing_required_names.items())
                ) or "none"
                pydantic_summary = ",".join(
                    f"{name}:{count}" for name, count in sorted(pydantic_error_types.items())
                ) or "none"
                logger.info(
                    "record preference analysis degraded stage=record_validation finish_reason=%s "
                    "record_failure_counts=%s missing_required_fields=%s pydantic_error_types=%s "
                    "evidence_rejected_facets=%d provider_analyzed=%d local_fallback=%d",
                    finish_reason, failure_summary, missing_summary, pydantic_summary,
                    evidence_rejected_facets, len(parsed_by_id), fallback_count,
                )
            logger.info(
                "record preference analysis complete http_status=%s finish_reason=%s json_parse=ok "
                "records_array_count=%d required_fields_validated=%d pydantic_validated=%d "
                "evidence_accepted_facets=%d source=provider provider_analyzed=%d local_fallback=%d",
                http_status, finish_reason, records_array_count, required_fields_validated_count,
                pydantic_validated_count, evidence_accepted_facet_count, len(parsed_by_id), fallback_count,
            )
            return self._filter_category(RecordPreferenceAnalysisResponse(analyses=analyses), category)
        except (httpx.HTTPError, KeyError, IndexError, TypeError, ValueError, ValidationError) as exc:
            response = getattr(exc, "response", None)
            status = getattr(response, "status_code", None)
            provider_error_code = "unavailable"
            provider_error_param = "unavailable"
            provider_error_schema_keyword = "unavailable"
            if response is not None:
                try:
                    error_payload = response.json()
                    error_object = error_payload.get("error", {}) if isinstance(error_payload, dict) else {}
                    raw_code = error_object.get("code") or error_object.get("type") if isinstance(error_object, dict) else None
                    if isinstance(raw_code, (str, int)) and _SAFE_PROVIDER_CODE.fullmatch(str(raw_code)):
                        provider_error_code = str(raw_code)
                    provider_error_param, provider_error_schema_keyword = self._safe_provider_diagnostics(error_object)
                except (ValueError, TypeError, AttributeError):
                    pass
            error_category = (
                "rate_limited" if status == 429 else
                "authentication_or_authorization" if status in {401, 403} else
                "invalid_request_or_schema_compatibility" if status == 400 else
                "provider_server_error" if status is not None and status >= 500 else
                "provider_http_error" if status is not None else
                "transport_or_response_validation_error"
            )
            failure_stage = exc.stage if isinstance(exc, _AnalysisResponseFailure) else stage
            failure_reason = exc.reason if isinstance(exc, _AnalysisResponseFailure) else type(exc).__name__
            logger.info("record preference analysis unavailable source=local_fallback stage=%s reason=%s finish_reason=%s "
                        "http_status=%s "
                        "provider_error_category=%s provider_error_code=%s provider_error_param=%s "
                        "provider_error_schema_keyword=%s records=%d",
                        failure_stage, failure_reason, finish_reason,
                        status if status is not None else "none", error_category,
                        provider_error_code, provider_error_param, provider_error_schema_keyword, len(selected))
            # Keep only literal local evidence and known place types. No retry
            # is issued, and no preference is synthesized from generic words.
            unavailable = [item.model_copy(update={"evidence_status": EvidenceStatus.UNAVAILABLE}) for item in base]
            return self._filter_category(RecordPreferenceAnalysisResponse(analyses=unavailable), category)

    @staticmethod
    def _base_analysis(record: RecommendationRecord, metadata: RecordPlaceMetadata | None) -> RecordPreferenceAnalysis:
        place_type, label, evidence = _record_type_hint(record, metadata)
        facets = RecordPreferenceAnalysisService._literal_fallback_facets(record, place_type)
        trusted_categories = set(RecordPreferenceAnalysisService._categories_for(place_type))
        fallback_categories = {category for facet in facets for category in facet.categories}
        categories = sorted(trusted_categories or fallback_categories, key=lambda value: value.value)
        if trusted_categories:
            facets = [facet.model_copy(update={
                "categories": [value for value in facet.categories if value in trusted_categories]
            }) for facet in facets if not facet.categories or set(facet.categories).intersection(trusted_categories)]
        evidence_status = EvidenceStatus.PARTIAL if categories or facets else EvidenceStatus.UNKNOWN
        return RecordPreferenceAnalysis(
            record_id=record.record_id,
            place_name=record.place_name,
            place_type=place_type,
            place_type_label=label,
            place_type_evidence=evidence,
            categories=categories,
            emotion=record.emotion_code,
            emotion_intensity=_EMOTION_STRENGTH[record.emotion_code],
            facets=facets,
            evidence_status=evidence_status,
        )

    @staticmethod
    def _literal_fallback_facets(record: RecommendationRecord, place_type: PlaceType) -> list[PreferenceFacet]:
        if record.emotion_code not in _POSITIVE:
            return []
        content = record.content or ""
        place_categories = set(RecordPreferenceAnalysisService._categories_for(place_type))
        selected: list[tuple[str, FacetTargetKind, RecommendationCategory | None, int, int]] = []
        occupied: list[tuple[int, int]] = []
        for term, kind, category in sorted(_FALLBACK_TERMS, key=lambda item: len(item[0]), reverse=True):
            start = content.find(term)
            if start < 0:
                continue
            end = start + len(term)
            if any(start < old_end and end > old_start for old_start, old_end in occupied):
                continue
            if place_categories and category is not None and category not in place_categories:
                continue
            if category is None:
                categories = place_categories
            elif place_categories:
                categories = {category} if category in place_categories else set()
            else:
                categories = {category}
            quote_start, quote_end = max(0, start - 18), min(len(content), end + 18)
            quote = _redact_and_limit(content[quote_start:quote_end])
            if term not in quote:
                continue
            selected.append((term, kind, category if category and categories else None, start, end))
            occupied.append((start, end))
        facets = []
        for term, kind, inferred_category, _, _ in selected:
            categories = ([inferred_category] if inferred_category else list(place_categories))
            features = [term] if kind not in {FacetTargetKind.MENU, FacetTargetKind.DRINK, FacetTargetKind.FOOD} else []
            start = content.find(term)
            quote = _redact_and_limit(content[max(0, start - 18):min(len(content), start + len(term) + 18)])
            facets.append(PreferenceFacet(
                target_kind=kind, target_text=term, features=features, categories=categories,
                polarity="liked", evidence=quote, confidence=0.55,
            ))
        return facets[:12]

    @staticmethod
    def _categories_for(place_type: PlaceType) -> list[RecommendationCategory]:
        mapping = {
            PlaceType.FOOD: [RecommendationCategory.FOOD],
            PlaceType.BAR: [RecommendationCategory.BAR, RecommendationCategory.FOOD],
            PlaceType.CAFE: [RecommendationCategory.CAFE],
            PlaceType.NATURE: [RecommendationCategory.NATURE],
            PlaceType.ACTIVITY: [RecommendationCategory.ACTIVITY],
            PlaceType.UNKNOWN: [],
        }
        return mapping[place_type]

    @classmethod
    def _validate_evidence(cls, analysis: RecordPreferenceAnalysis, record: RecommendationRecord,
                           metadata: RecordPlaceMetadata | None,
                           diagnostics: Counter[str] | None = None) -> RecordPreferenceAnalysis:
        source_text = f"{record.place_name or ''} {record.content}"
        normalized_source = _norm(source_text)
        # Locally trusted metadata and explicit name rules outrank model guesses.
        trusted_type, trusted_label, trusted_evidence = _record_type_hint(record, metadata)
        if trusted_type != PlaceType.UNKNOWN:
            place_type, label, type_evidence = trusted_type, trusted_label, trusted_evidence
            if trusted_evidence == "record_context_hint" and diagnostics is not None:
                diagnostics["place_type_recovered_from_record_context"] += 1
        else:
            type_quote = _norm(analysis.place_type_evidence)
            # LLM evidence must quote record content. Place-name type evidence
            # is accepted only through the conservative local name rules above.
            type_supported = bool(type_quote and (type_quote in _norm(record.content)
                                                  or type_quote == _norm(record.place_name)))
            if analysis.place_type != PlaceType.UNKNOWN and not type_supported and diagnostics is not None:
                diagnostics["place_type_evidence_not_in_record"] += 1
            place_type = analysis.place_type if type_supported else PlaceType.UNKNOWN
            label = analysis.place_type_label if type_supported else None
            type_evidence = "record_quote" if type_supported else None

        valid_facets = []
        positive_record = record.emotion_code in _POSITIVE
        for facet in analysis.facets:
            quote = _norm(facet.evidence)
            target = _norm(facet.target_text)
            content_norm = _norm(record.content)
            target_present = target and (target in content_norm or target in _norm(record.place_name))
            quote_present = quote and quote in normalized_source
            features_present = all(_norm(feature) and _norm(feature) in content_norm for feature in facet.features)
            negative_feature = _has_explicit_negative_span(" ".join(facet.features))
            if facet.polarity == "liked":
                polarity_ok = positive_record and not negative_feature
            elif facet.polarity == "disliked":
                polarity_ok = _has_explicit_negative_span(
                    " ".join([facet.target_text, *facet.features])
                )
            else:
                polarity_ok = True
            if not (target_present and quote_present and features_present and polarity_ok):
                if diagnostics is not None:
                    if not target_present:
                        diagnostics["target_not_in_record"] += 1
                    if not quote_present:
                        diagnostics["evidence_quote_not_in_record"] += 1
                    if not features_present:
                        diagnostics["feature_not_in_record"] += 1
                    if not polarity_ok:
                        diagnostics["polarity_conflicts_with_emotion"] += 1
                continue
            valid_facets.append(facet)

        categories = cls._categories_for(place_type)
        literal_facets = cls._literal_fallback_facets(record, PlaceType.UNKNOWN)
        literal_category_support: dict[str, set[RecommendationCategory]] = {}
        for literal in literal_facets:
            literal_category_support.setdefault(_norm(literal.target_text), set()).update(literal.categories)
        # Keep LLM facets only where their categories agree with a trusted
        # place type or a literal, category-bearing term in this record.
        filtered_facets = []
        for facet in valid_facets:
            if place_type != PlaceType.UNKNOWN:
                facet_categories = categories[:]
            else:
                facet_terms = {_norm(facet.target_text), *(_norm(value) for value in facet.features)}
                supported_categories = set().union(*(
                    values for target, values in literal_category_support.items()
                    if target and any(target in term or term in target for term in facet_terms if term)
                )) if literal_category_support else set()
                facet_categories = sorted(supported_categories, key=lambda value: value.value)
                if facet_categories and diagnostics is not None:
                    diagnostics["facet_domain_recovered_from_literal_term"] += 1
            if facet_categories:
                filtered_facets.append(facet.model_copy(update={"categories": facet_categories}))
            elif place_type == PlaceType.UNKNOWN:
                # Provider-supplied category labels alone are not evidence of
                # the venue or preference domain.
                filtered_facets.append(facet.model_copy(update={"categories": []}))
        if place_type == PlaceType.UNKNOWN:
            categories = sorted({value for facet in filtered_facets for value in facet.categories},
                                key=lambda value: value.value)
        if filtered_facets:
            status = EvidenceStatus.VERIFIED if place_type != PlaceType.UNKNOWN and len(filtered_facets) == len(analysis.facets) else EvidenceStatus.PARTIAL
        elif place_type != PlaceType.UNKNOWN:
            status = EvidenceStatus.PARTIAL
        else:
            status = EvidenceStatus.UNKNOWN
        return analysis.model_copy(update={
            "place_type": place_type,
            "place_type_label": label,
            "place_type_evidence": type_evidence,
            "categories": categories,
            "facets": filtered_facets,
            "evidence_status": status,
        })

    @staticmethod
    def _filter_category(response: RecordPreferenceAnalysisResponse,
                         category: RecommendationCategory) -> RecordPreferenceAnalysisResponse:
        if category == RecommendationCategory.ALL:
            return response
        scoped = []
        for analysis in response.analyses:
            if category not in analysis.categories:
                continue
            facets = [facet for facet in analysis.facets if category in facet.categories]
            scoped.append(analysis.model_copy(update={"facets": facets}))
        return RecordPreferenceAnalysisResponse(analyses=scoped)
