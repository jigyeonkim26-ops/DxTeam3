"""Evidence-grounded analysis and bounded offline fallback for record preferences.

The category-v3 recommendation API consumes this module. Optional trusted
place-category metadata can be supplied without a database schema change.
"""

from __future__ import annotations

import json
import logging
import re
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
        if any(term.strip() in name for term in terms):
            return place_type, place_name, "place_name_hint"
    return PlaceType.UNKNOWN, None, None


def _parse_json(content: Any) -> dict[str, Any]:
    if not isinstance(content, str):
        raise ValueError("response content must be text")
    text = content.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[-1].rsplit("```", 1)[0].strip()
    start = text.find("{")
    if start < 0:
        raise ValueError("JSON object is missing")
    parsed, _ = json.JSONDecoder().raw_decode(text[start:])
    if not isinstance(parsed, dict) or not isinstance(parsed.get("records"), list):
        raise ValueError("records array is missing")
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
            logger.info("record preference analysis unavailable reason=missing_configuration records=%d", len(selected))
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
                    "Analyze each memory independently. Return only the required JSON. "
                    "Extract multiple positive or negative target-feature relations when explicit. "
                    "target_text must be a literal short span from place_name or content; features must be explicit terms from content. "
                    "evidence must be an exact short quote from input place_name or content. Never infer a target (e.g. parking) from a generic feature (e.g. spacious). "
                    "Use trusted_category/place_type_hint first. Otherwise infer place type only when evidence is explicit; use unknown if uncertain. "
                    "Use category all plus relevant specific categories. Do not transfer a preference between unrelated place types. "
                    "For negative emotions, only mark explicit dislikes and do not turn them into liked preferences. Do not invent facts."
                )},
                {"role": "user", "content": json.dumps({"records": record_inputs}, ensure_ascii=False)},
            ],
            "response_format": {"type": "json_schema", "json_schema": self._SCHEMA},
            "provider": {"require_parameters": True},
            "temperature": 0,
            "max_tokens": min(3000, 180 + 140 * len(selected)),
            "stream": False,
        }
        try:
            response = self._post_json(self.API_URL, headers={
                "Authorization": f"Bearer {self.api_key}", "Content-Type": "application/json",
            }, json=payload, timeout=35.0)
            response.raise_for_status()
            content = response.json()["choices"][0]["message"]["content"]
            raw = _parse_json(content)
            parsed_by_id = {}
            base_by_id = {item.record_id: item for item in base}
            required_fields = {"record_id", "place_type", "place_type_label", "place_type_evidence", "categories", "facets"}
            for raw_item in raw["records"]:
                record_id = raw_item.get("record_id") if isinstance(raw_item, dict) else None
                if record_id not in allowed_ids or record_id in parsed_by_id:
                    continue
                if not required_fields.issubset(raw_item):
                    raise ValueError("analysis record is missing required fields")
                # Emotion, strength, and source place name are deterministic input
                # facts, not fields the model is allowed to rewrite.
                item_data = base_by_id[record_id].model_dump()
                for field in ("place_type", "place_type_label", "place_type_evidence", "categories", "facets"):
                    if field in raw_item:
                        item_data[field] = raw_item[field]
                item = RecordPreferenceAnalysis.model_validate(item_data)
                source = next(record for record in selected if record.record_id == record_id)
                item = self._validate_evidence(item, source, metadata.get(source.record_id))
                parsed_by_id[item.record_id] = item
            analyses = [parsed_by_id.get(record.record_id, base[index]) for index, record in enumerate(selected)]
            logger.info("record preference analysis complete records=%d analyzed=%d", len(selected), len(parsed_by_id))
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
            logger.info("record preference analysis unavailable reason=%s http_status=%s "
                        "provider_error_category=%s provider_error_code=%s provider_error_param=%s "
                        "provider_error_schema_keyword=%s records=%d",
                        type(exc).__name__, status if status is not None else "none", error_category,
                        provider_error_code, provider_error_param, provider_error_schema_keyword, len(selected))
            # Keep only literal local evidence and known place types. No retry
            # is issued, and no preference is synthesized from generic words.
            unavailable = [item.model_copy(update={"evidence_status": EvidenceStatus.UNAVAILABLE}) for item in base]
            return self._filter_category(RecordPreferenceAnalysisResponse(analyses=unavailable), category)

    @staticmethod
    def _base_analysis(record: RecommendationRecord, metadata: RecordPlaceMetadata | None) -> RecordPreferenceAnalysis:
        place_type, label, evidence = _metadata_type(metadata)
        if place_type == PlaceType.UNKNOWN:
            place_type, label, evidence = _name_type(record.place_name)
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
                           metadata: RecordPlaceMetadata | None) -> RecordPreferenceAnalysis:
        source_text = f"{record.place_name or ''} {record.content}"
        normalized_source = _norm(source_text)
        # Locally trusted metadata and explicit name rules outrank model guesses.
        trusted_type, trusted_label, trusted_evidence = _metadata_type(metadata)
        if trusted_type == PlaceType.UNKNOWN:
            trusted_type, trusted_label, trusted_evidence = _name_type(record.place_name)
        if trusted_type != PlaceType.UNKNOWN:
            place_type, label, type_evidence = trusted_type, trusted_label, trusted_evidence
        else:
            type_quote = _norm(analysis.place_type_evidence)
            type_supported = bool(type_quote and type_quote in normalized_source)
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
            polarity_ok = (facet.polarity == "liked") if positive_record else (facet.polarity != "liked")
            if not (target_present and quote_present and features_present and polarity_ok):
                continue
            valid_facets.append(facet)

        categories = cls._categories_for(place_type)
        # Keep LLM facets only where their categories agree with known place type.
        filtered_facets = []
        for facet in valid_facets:
            facet_categories = list(dict.fromkeys(facet.categories))
            if place_type != PlaceType.UNKNOWN:
                facet_categories = [value for value in facet_categories if value in categories]
                if not facet_categories:
                    facet_categories = categories[:]
            filtered_facets.append(facet.model_copy(update={"categories": facet_categories}))
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
