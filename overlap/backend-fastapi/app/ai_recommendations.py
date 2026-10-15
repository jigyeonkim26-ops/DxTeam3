"""Authenticated AI recommendation endpoint over existing database records."""

import logging
import hashlib
import json
import re
import time
from collections import OrderedDict

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from .ai_recommendation_errors import AIConfigurationError, AIRecommendationError, AIResponseError, InvalidRecommendationError
from . import recommendation_diagnostics as diagnostics
from .ai_recommendation_models import PlaceRecommendationResponse, RecommendedPlace
from .config import LLM_PROVIDER, SEARCH_PROVIDER
from .records import require_db
from .recommendation_record_adapter import RecordRecommendationAdapter
from .kakao_place_verification_service import KakaoPlaceVerificationService
from .provider_factory import build_preference_service, build_recommendation_service, build_search_service
from .recommendation_image_service import RecommendationImageService
from .place_candidate_search_service import (
    CategoryMatchStatus,
    CandidateSearchResult,
    FeatureEvidenceStatus,
    PlaceCandidateSearchService,
    ProviderStatus,
)
from .record_preference_analysis import (
    EvidenceStatus,
    PlaceType,
    RecordPreferenceAnalysisService,
    RecommendationCategory,
)

# Uvicorn configures this logger with its console error handler.
logger = logging.getLogger("uvicorn.error")

_PAGE_SIZE = 3
_MAX_POOL_SIZE = 10
_SESSION_TTL_SECONDS = 20 * 60
_EMPTY_SESSION_RETRY_COOLDOWN_SECONDS = 30
_EMPTY_SESSION_MAX_RETRIES = 2
_CATEGORY_PIPELINE_VERSION = "category-v6"
_LEGACY_PIPELINE_VERSION = "legacy-tavily-v2"
_CATEGORY_AFFINITY_MIN_RECORDS = 3
_CATEGORY_AFFINITY_MIN_DISTINCT_TARGETS = 2


def _normalized(value: str | None) -> str:
    return re.sub(r"[^\w]", "", (value or "").casefold(), flags=re.UNICODE)


# Small, explicit Korean concept groups cover common paraphrases that occur in
# place descriptions. They provide source-text support without making the
# suitability decision depend on the LLM's score or an unbounded fuzzy match.
_PREFERENCE_CONCEPTS = (
    frozenset(("노을", "석양", "일몰", "해질녘", "해넘이", "낙조", "sunset", "dusk")),
    frozenset(("산책", "산책로", "걷기", "걷는", "걷다", "걸을수", "걷기좋은", "둘러보기", "둘레길", "트레킹", "보행", "walking")),
    frozenset(("전망", "조망", "뷰", "내려다보다", "바라보다", "뷰포인트", "탁트인풍경", "풍경감상", "viewpoint")),
    frozenset(("조용", "한적", "평온", "고요", "차분")),
    frozenset(("자연", "숲", "녹지", "정원", "나무", "자연경관")),
)
_SEMANTIC_PLACE_CONTEXTS = (
    # A scenic place type plus a scenic-description cue can support sunset
    # viewing even when the literal word "sunset" is absent.
    (("노을", "석양", "일몰", "해질녘", "해넘이", "낙조"),
     ("공원", "전망대", "강변", "수변", "산책로", "언덕"),
     ("전망", "조망", "풍경", "경관", "뷰", "탁트인")),
)


def _preference_evidence_terms(keyword: str) -> frozenset[str]:
    normalized = _normalized(keyword)
    for concept in _PREFERENCE_CONCEPTS:
        normalized_concept = {_normalized(term) for term in concept}
        if any(term and (term in normalized or normalized in term) for term in normalized_concept):
            return frozenset(normalized_concept)
    return frozenset((normalized,))


def _supported_preference_terms(candidate, keywords) -> list[str]:
    """Return preferences with auditable evidence in Kakao/Tavily candidate data."""
    evidence = _normalized(f"{candidate.name} {candidate.summary}")
    matched = []
    for preference in keywords:
        terms = _preference_evidence_terms(preference.keyword)
        direct_match = any(len(term) >= 2 and term in evidence for term in terms)
        semantic_match = False
        if not direct_match:
            normalized_preference = _normalized(preference.keyword)
            for aliases, place_types, description_cues in _SEMANTIC_PLACE_CONTEXTS:
                normalized_aliases = [_normalized(alias) for alias in aliases]
                if not any(alias in normalized_preference for alias in normalized_aliases):
                    continue
                has_place_type = any(_normalized(term) in evidence for term in place_types)
                has_description_cue = any(_normalized(term) in evidence for term in description_cues)
                semantic_match = has_place_type and has_description_cue
                if semantic_match:
                    break
        if direct_match or semantic_match:
            matched.append(preference.keyword)
    return matched


def _preference_evidence_score(candidate, keywords) -> tuple[float, list[str]]:
    """Fixed evidence rubric (not a probability or an LLM-provided score).

    Each match must appear in the verified place name or supplied description.
    Preference importance weights contribution; a modest fixed threshold allows
    one well-supported preference while rejecting generic Kakao-only results.
    """
    supported = _supported_preference_terms(candidate, keywords)
    if not supported or not keywords:
        return 0.0, supported
    weights = {item.keyword: 0.5 + item.score for item in keywords}
    strongest = max(weights.values(), default=0.0)
    supported_weight = sum(weights.get(term, 0.0) for term in supported)
    # Description evidence is stronger than a name-only coincidence. A generic
    # Kakao fallback has no supported terms and therefore remains at zero.
    description = _normalized(candidate.summary)
    description_matches = sum(
        weights.get(term, 0.0) for term in supported
        if any(len(token) >= 2 and token in description for token in _preference_evidence_terms(term))
    )
    preference_strength = max((weights.get(term, 0.0) for term in supported), default=0.0)
    preference_strength = preference_strength / strongest if strongest else 0.0
    description_support = description_matches / supported_weight if supported_weight else 0.0
    # One clear, lower-priority preference can still qualify a good place;
    # support for more preferences increases rank without imposing a breadth gate.
    score = min(1.0, preference_strength * 0.65 + description_support * 0.35)
    return round(score, 4), supported


def _filter_suitable_candidates(candidates, keywords):
    eligible = []
    seen_ids = set()
    for candidate in candidates:
        place_id = candidate.kakao_place_id
        if not place_id or place_id in seen_ids:
            continue
        if not candidate.name.strip() or not candidate.address or candidate.latitude is None or candidate.longitude is None:
            continue
        score, _ = _preference_evidence_score(candidate, keywords)
        if score >= 0.18:
            seen_ids.add(place_id)
            eligible.append(candidate)
    return eligible


def _fallback_recommendations(candidates, keywords):
    """Use only already-qualified Kakao places and quote their supplied evidence."""
    ranked = []
    for candidate in candidates:
        score, matched = _preference_evidence_score(candidate, keywords)
        if score < 0.18 or not matched:
            continue
        ranked.append((score, candidate, matched))
    ranked.sort(key=lambda row: row[0], reverse=True)
    output = []
    for score, candidate, matched in ranked[:_MAX_POOL_SIZE]:
        evidence = " ".join(candidate.summary.split())[:220]
        reason = f"기록에서 확인된 '{', '.join(matched)}' 선호와 장소 설명의 근거를 바탕으로 추천합니다: {evidence}"
        output.append(RecommendedPlace(
            rank=len(output) + 1,
            kakao_place_id=candidate.kakao_place_id,
            name=candidate.name,
            address=candidate.address,
            latitude=candidate.latitude,
            longitude=candidate.longitude,
            match_score=score,
            matched_keywords=matched,
            reason=reason[:500],
            source_url=candidate.source_url,
        ))
    return output


def _records_fingerprint(records) -> str:
    snapshot = [record.model_dump(mode="json") for record in records]
    payload = json.dumps(snapshot, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _analysis_cache_decision(analyses) -> tuple[bool, str]:
    """Cache reusable successful records, but not all-empty category analysis."""
    rows = getattr(analyses, "analyses", [])
    reusable = [item for item in rows if item.evidence_status != EvidenceStatus.UNAVAILABLE]
    if not reusable:
        return False, "all_records_unavailable"
    if rows and len(reusable) / len(rows) < 0.40:
        return False, "provider_coverage_below_40_percent"
    has_specific_category = any(
        any(value != RecommendationCategory.ALL for value in item.categories)
        for item in reusable
    )
    has_unscoped_facets = any(item.facets and not item.categories for item in reusable)
    if not has_specific_category and has_unscoped_facets:
        return False, "all_categories_unresolved_with_facets"
    return True, "partial_or_complete_analysis"


def _invalidate_empty_session(sessions, key) -> bool:
    session = sessions.get(key)
    if session is None or session.get("recommendations") or session.get("empty_complete"):
        return False
    sessions.pop(key, None)
    return True


def _empty_session_retry_state(session: dict, now: float) -> tuple[bool, dict]:
    """Allow a bounded explicit retry for empty results after a short cooldown."""
    retries = int(session.get("empty_retry_count", 0))
    last_attempt = float(session.get("last_empty_retry_at", session.get("created_at", now)))
    can_retry = (retries < _EMPTY_SESSION_MAX_RETRIES
                 and now - last_attempt >= _EMPTY_SESSION_RETRY_COOLDOWN_SECONDS)
    return can_retry, {
        "empty_retry_count": retries + int(can_retry),
        "last_empty_retry_at": now if can_retry else last_attempt,
    }


def _log_diagnostic(stage: str, count: int) -> None:
    """Record count-only AI pipeline diagnostics without request or provider data."""
    logger.info("AI recommendation diagnostic %s=%d", stage, count)


def _log_provider_failure(stage: str, error: AIRecommendationError) -> None:
    """Log only safe diagnostics; provider payloads and credentials are never logged."""
    cause = error.__cause__
    response = getattr(cause, "response", None)
    status = getattr(response, "status_code", None)
    logger.error(
        "AI recommendation provider failure stage=%s exception=%s cause=%s http_status=%s message=%s",
        stage,
        type(error).__name__,
        type(cause).__name__ if cause is not None else "none",
        status if status is not None else "none",
        "provider request failed",
    )


def _infer_region(records) -> str | None:
    """Select the most frequent available province/city-or-district prefix from records."""
    counts: dict[str, int] = {}
    for record in records:
        parts = (record.address or "").split()
        if parts:
            # A newly consolidated province can cover several distant cities.
            # Preserve the most specific locality present in the stored address.
            area_index = 2 if (len(parts) > 2 and parts[0] == "전남광주통합특별시"
                               and parts[1] in {"광주", "광주시", "광주광역시"}) else 1
            locality = " ".join(parts[:area_index + 1])
            counts[locality] = counts.get(locality, 0) + 1
    return max(counts, key=counts.get) if counts else None


def _natural_personalized_reason(keyword: str, place_name: str, kind: str,
                                 place_type: str = "") -> str:
    """Phrase only the verified preference and the candidate fact already gated above."""
    keyword = keyword.strip().strip("'\"‘’“”")
    place_name = place_name.strip()
    place_type = place_type.strip()
    # Stable per keyword/place variation avoids one repeated sentence pattern
    # without introducing randomness into API responses or test results.
    variant = sum(ord(char) for char in f"{keyword}:{place_name}") % 2
    if kind in {"menu", "drink", "food"}:
        if variant:
            return (f"지난번에 {keyword} 맛있게 드셨잖아요. "
                    f"{keyword}가 있는 {place_name}도 취향에 맞을 것 같아요!")
        return (f"{keyword} 맛있게 드셨던 기억이 있죠? "
                f"{place_name}에서도 {keyword}를 맛볼 수 있다니, 한번 들러보세요!")
    if kind == "nature":
        if place_type and any(term in place_type for term in ("산책로", "숲길", "둘레길", "등산로")):
            return (f"산책하며 보냈던 시간이 좋으셨죠? 이번에는 "
                    f"{place_name}의 {place_type}도 걸어보는 건 어때요?")
        return f"{keyword} 좋아하셨죠? 이번에는 {place_name}도 천천히 둘러보는 건 어때요?"
    if kind in {"space", "atmosphere"}:
        space_preference = keyword
        if not any(word in keyword for word in ("공간", "카페", "분위기")):
            space_preference = f"{keyword} 공간"
        return f"{space_preference}을 좋아하셨죠? {place_name}도 한번 들러보는 건 어때요?"
    if kind == "activity":
        return f"{keyword} 좋아하셨죠? {place_name}도 한번 둘러보는 건 어때요?"
    if variant:
        return f"{keyword} 취향이 떠오르네요. {place_name}도 한번 가보는 건 어때요?"
    return f"{keyword} 좋아하셨죠? 이번에는 {place_name}도 눈여겨보세요!"


def _category_label(category: RecommendationCategory) -> str:
    return {
        RecommendationCategory.ALL: "확인된 분야",
        RecommendationCategory.FOOD: "음식점",
        RecommendationCategory.BAR: "술집",
        RecommendationCategory.CAFE: "카페",
        RecommendationCategory.NATURE: "자연·산책 장소",
        RecommendationCategory.ACTIVITY: "문화·스포츠 장소",
    }[category]


def _kakao_nature_type_support(facet, item) -> bool:
    """Kakao category paths prove POI type only, never scenic details."""
    if (facet.polarity != "liked"
            or item.classification.status != CategoryMatchStatus.CONFIRMED
            or RecommendationCategory.NATURE not in item.classification.categories):
        return False
    category_text = _normalized(item.place.category_name or "")
    preference_parts = [_normalized(value) for value in [facet.target_text, *facet.features]]
    suffixes = ("을", "를", "이", "은", "는", "하기", "했던", "하며", "하고", "좋아함", "좋았다")
    def has_recorded_term(terms):
        for part in preference_parts:
            for term in terms:
                key = _normalized(term)
                if part == key or any(part == key + suffix for suffix in suffixes):
                    return True
        return False
    groups = (
        (("산책", "걷기", "걸을", "트레킹", "둘레길"), ("산책로", "둘레길", "공원", "숲길")),
        (("등산", "산행", "등산로"), ("등산로", "산", "산림")),
        (("숲", "자연", "자연경관"), ("숲", "수목원", "자연", "생태", "산림")),
        # Scenic preferences require a Kakao type that denotes a view.
        # Generic tourist or nature-attraction labels do not prove scenery.
        (("\uC804\uB9DD", "\uD48D\uACBD", "\uC870\uB9DD", "\uBDF0"), ("\uC804\uB9DD\uB300",)),
        (("공원", "수목원"), ("공원", "수목원")),
    )
    return bool(any(
        has_recorded_term(preferences)
        and any(_normalized(kind) in category_text for kind in venue_types)
        for preferences, venue_types in groups
    ))


def _kakao_specific_category_type_support(
    facet, item, *, polarity: str = "liked",
) -> tuple[RecommendationCategory, str] | None:
    """Match a specific Kakao subtype to a recorded facet without a fixed term list."""
    if facet.polarity != polarity or item.classification.status != CategoryMatchStatus.CONFIRMED:
        return None
    candidate_categories = set(item.classification.categories)
    eligible_categories = {
        RecommendationCategory.FOOD, RecommendationCategory.BAR,
        RecommendationCategory.CAFE, RecommendationCategory.ACTIVITY,
    }
    matching_categories = [category for category in facet.categories
                           if category in candidate_categories and category in eligible_categories]
    if not matching_categories:
        return None

    # A leaf subtype must be present in Kakao's category path and must be
    # narrower than its top-level category. Generic business labels alone do
    # not provide B-level evidence.
    category_parts = [part.strip() for part in (item.place.category_name or "").split(">") if part.strip()]
    if len(category_parts) < 2:
        return None
    subtype = category_parts[-1]
    subtype_key = _normalized(subtype)
    top_level_key = _normalized(category_parts[0])
    generic_labels = {
        _normalized(value) for value in (
            "음식점", "식당", "restaurant", "카페", "cafe", "술집", "bar",
            "문화시설", "문화예술", "관광명소", "기타", "일반",
        )
    }
    if not subtype_key or subtype_key == top_level_key or subtype_key in generic_labels:
        return None

    preference_terms = [facet.target_text, *facet.features]
    for term in preference_terms:
        term_key = _normalized(term)
        if not term_key:
            continue
        # The comparison is dynamic: it uses only the recorded facet and the
        # Kakao leaf type, with no per-dish or per-venue synonym table.
        if subtype_key == term_key or (len(subtype_key) >= 3 and subtype_key in term_key) or (
            len(term_key) >= 3 and term_key in subtype_key
        ):
            return matching_categories[0], subtype
    return None


def _category_type_reason(keyword: str, place_name: str, place_type: str) -> str:
    return f"{keyword} 좋아하셨죠? {place_type}인 {place_name}도 취향에 맞을지 둘러보는 건 어때요?"


def _repeated_positive_category_affinity(analyses, candidate_categories):
    """Return category-level affinity only when it repeats across distinct records.

    Specific facet repetition alone is not widened into a field preference:
    with facets present, at least two distinct recorded targets are required.
    Repeated positive records with no specific facets can establish a broad
    field preference, but cannot support claims about a particular feature.
    """
    candidates = []
    for category in candidate_categories:
        by_record = {}
        targets = set()
        facetless_records = set()
        for analysis in analyses.analyses:
            if category not in analysis.categories:
                continue
            emotion = getattr(analysis.emotion, "value", analysis.emotion)
            if emotion not in {"LOVE", "LIKE", "GOOD"}:
                continue
            if analysis.evidence_status not in {EvidenceStatus.VERIFIED, EvidenceStatus.PARTIAL}:
                continue
            relevant_facets = [facet for facet in analysis.facets
                               if facet.polarity == "liked" and category in facet.categories]
            if analysis.facets and not relevant_facets:
                continue
            by_record[analysis.record_id] = analysis
            if relevant_facets:
                targets.update(_normalized(facet.target_text) for facet in relevant_facets
                               if _normalized(facet.target_text))
            else:
                facetless_records.add(analysis.record_id)

        enough_records = len(by_record) >= _CATEGORY_AFFINITY_MIN_RECORDS
        enough_breadth = (len(targets) >= _CATEGORY_AFFINITY_MIN_DISTINCT_TARGETS
                          or len(facetless_records) >= _CATEGORY_AFFINITY_MIN_RECORDS)
        candidates.append((category, by_record, len(targets), enough_records and enough_breadth))
    return max(candidates, key=lambda value: (value[3], len(value[1]), value[2]), default=None)


def _build_category_recommendations(search_result, analyses, category: RecommendationCategory):
    """Rank personalized A/B candidates; exclude category-only C."""
    ranking_started = time.perf_counter()
    ranked = []
    category_only_excluded = 0
    confirmed_evidence_count = 0
    same_record_evidence_count = 0
    linked_facet_evidence_count = 0
    def label(value):
        return {
            RecommendationCategory.FOOD: "\uC74C\uC2DD\uC810",
            RecommendationCategory.BAR: "\uC220\uC9D1",
            RecommendationCategory.CAFE: "\uCE74\uD398",
            RecommendationCategory.NATURE: "\uC790\uC5F0\u00B7\uC0B0\uCC45 \uC7A5\uC18C",
            RecommendationCategory.ACTIVITY: "\uBB38\uD654\u00B7\uC2A4\uD3EC\uCE20 \uC7A5\uC18C",
        }.get(value, "\uC7A5\uC18C")

    for item in search_result.candidates:
        place = item.place
        if item.classification.status != CategoryMatchStatus.CONFIRMED:
            code = (place.category_group_code or "").upper()
            group_code_classes = {"FD6": "food", "CE7": "cafe", "AT4": "tourism", "CT1": "culture"}
            non_target_codes = {"PK6", "SC4", "AC5", "AD5", "BK9", "CS2", "HP8", "OL7", "PO3", "SW8", "AG2", "MT1"}
            group_code_class = group_code_classes.get(code, "non_target" if code in non_target_codes else "unknown")
            evidence_sources = item.classification.evidence
            category_name_mapping = [
                source.split(":", 1)[1] for source in evidence_sources
                if source.startswith("kakao_category_name:")
            ]
            category_name_mapped = bool(category_name_mapping)
            category_reason = (
                "category_requires_specific_subtype"
                if item.classification.status == CategoryMatchStatus.VERIFICATION_REQUIRED
                else "known_category_mismatch"
                if item.classification.status == CategoryMatchStatus.MISMATCH
                else "no_recognized_category_evidence"
                if not item.classification.categories
                else "insufficient_category_evidence"
            )
            diagnostics.category_result(
                place.kakao_place_id,
                category_present=bool(place.category_group_code or place.category_name),
                group_code_class=group_code_class,
                category_name_mapped=category_name_mapped,
                category_name_mapping=category_name_mapping,
                mapped_categories=[value.value for value in item.classification.categories],
                status=item.classification.status.value,
                reason="confirmed" if item.classification.status == CategoryMatchStatus.CONFIRMED else category_reason,
            )
            diagnostics.personalization_result(
                place.kakao_place_id,
                categories=[value.value for value in item.classification.categories],
                positive_category_present=None, linkable_facet_count=None, matched_facet_count=None,
                type_evidence_accepted=None, result="rejected", reason="category_not_confirmed",
            )
            diagnostics.decision("ranking_category_gate", place.kakao_place_id, "rejected", "category_not_confirmed")
            _log_place_decision(pipeline=_CATEGORY_PIPELINE_VERSION, stage="final_category_gate",
                kakao_place_id=place.kakao_place_id, place_name=place.place_name,
                category_name=place.category_name, category_group_code=place.category_group_code,
                category_status=item.classification.status.value, decision="rejected", reason="category_not_confirmed")
            continue
        place_categories = set(item.classification.categories)
        negative_facets = [
            facet for analysis in analyses.analyses for facet in analysis.facets
            if facet.polarity == "disliked"
            and place_categories.intersection(facet.categories)
        ]
        negative_conflict = next((facet for facet in negative_facets
                                  if _kakao_specific_category_type_support(
                                      facet, item, polarity="disliked"
                                  )), None)
        if negative_conflict is not None:
            diagnostics.personalization_result(
                place.kakao_place_id,
                categories=[value.value for value in place_categories],
                positive_category_present=None, linkable_facet_count=None,
                matched_facet_count=0, type_evidence_accepted=False,
                result="rejected", reason="explicit_negative_type_conflict",
            )
            diagnostics.decision(
                "personalization_gate", place.kakao_place_id,
                "rejected", "explicit_negative_type_conflict",
            )
            continue
        facets = [(analysis, facet) for analysis in analyses.analyses for facet in analysis.facets
            if facet.polarity == "liked"
            and (category == RecommendationCategory.ALL or category in facet.categories)
            and (category == RecommendationCategory.ALL or category in analysis.categories)
            and place_categories.intersection(facet.categories)]
        affinity_categories = place_categories.intersection(
            {RecommendationCategory.FOOD, RecommendationCategory.BAR,
             RecommendationCategory.CAFE, RecommendationCategory.NATURE,
             RecommendationCategory.ACTIVITY}
        )
        if category != RecommendationCategory.ALL:
            affinity_categories.intersection_update({category})
        category_affinity_stats = _repeated_positive_category_affinity(analyses, affinity_categories)
        category_affinity = (category_affinity_stats
                             if category_affinity_stats and category_affinity_stats[3] else None)
        type_records = []
        type_support_by_record = {}
        for analysis, facet in facets:
            if (category in {RecommendationCategory.ALL, RecommendationCategory.NATURE}
                    and RecommendationCategory.NATURE in place_categories
                    and _kakao_nature_type_support(facet, item)):
                type_records.append((analysis, RecommendationCategory.NATURE))
                subtype = (item.place.category_name or "").split(">")[-1].strip() or "자연 장소"
                type_support_by_record.setdefault(
                    analysis.record_id, (facet, RecommendationCategory.NATURE, subtype)
                )
            else:
                type_support = _kakao_specific_category_type_support(facet, item)
                if type_support:
                    type_category, subtype = type_support
                    type_records.append((analysis, type_category))
                    type_support_by_record.setdefault(analysis.record_id, (facet, type_category, subtype))
        if not facets and not type_records and category_affinity is None:
            category_only_excluded += 1
            diagnostics.personalization_result(
                place.kakao_place_id,
                categories=[value.value for value in place_categories],
                positive_category_present=False, linkable_facet_count=0, matched_facet_count=0,
                type_evidence_accepted=False, result="rejected",
                reason=("category_affinity_below_threshold" if category_affinity_stats
                        else "no_positive_facet_for_confirmed_category"),
                category_affinity_record_count=(len(category_affinity_stats[1])
                                                if category_affinity_stats else 0),
                category_affinity_distinct_target_count=(category_affinity_stats[2]
                                                         if category_affinity_stats else 0),
            )
            diagnostics.decision("personalization_gate", place.kakao_place_id, "rejected", "no_matching_positive_record_category")
            _log_place_decision(pipeline=_CATEGORY_PIPELINE_VERSION, stage="personalized_relevance_gate",
                kakao_place_id=place.kakao_place_id, place_name=place.place_name,
                category_name=place.category_name, category_group_code=place.category_group_code,
                category_status=item.classification.status.value, decision="rejected",
                reason="no_matching_positive_record_category")
            continue
        verified = set()
        for evidence in item.preference_evidence:
            if evidence.status != FeatureEvidenceStatus.CONFIRMED or not evidence.evidence_url:
                continue
            confirmed_evidence_count += 1
            same_record_facets = [(analysis, facet) for analysis, facet in facets
                                  if analysis.record_id == evidence.record_id]
            if same_record_facets:
                same_record_evidence_count += 1
            for analysis, facet in facets:
                terms = {facet.target_text.casefold(), *(value.casefold() for value in facet.features)}
                if analysis.record_id == evidence.record_id and evidence.preference.casefold() in terms:
                    verified.add((analysis.record_id, evidence.preference.casefold()))
                    linked_facet_evidence_count += 1
        matched = [(analysis, facet) for analysis, facet in facets if any(
            analysis.record_id == record_id and term in {facet.target_text.casefold(), *(value.casefold() for value in facet.features)}
            for record_id, term in verified)]
        if not matched and not type_records and category_affinity is None:
            category_only_excluded += 1
            diagnostics.personalization_result(
                place.kakao_place_id,
                categories=[value.value for value in place_categories],
                positive_category_present=True, linkable_facet_count=len(facets), matched_facet_count=0,
                type_evidence_accepted=False, result="rejected",
                reason=("category_affinity_below_threshold" if category_affinity_stats
                        else "positive_facet_without_verified_feature"),
                category_affinity_record_count=(len(category_affinity_stats[1])
                                                if category_affinity_stats else 0),
                category_affinity_distinct_target_count=(category_affinity_stats[2]
                                                         if category_affinity_stats else 0),
            )
            diagnostics.decision("personalization_gate", place.kakao_place_id, "rejected", "no_candidate_specific_preference_evidence")
            _log_place_decision(pipeline=_CATEGORY_PIPELINE_VERSION, stage="personalized_relevance_gate",
                kakao_place_id=place.kakao_place_id, place_name=place.place_name,
                category_name=place.category_name, category_group_code=place.category_group_code,
                category_status=item.classification.status.value, decision="rejected",
                reason="no_candidate_specific_preference_evidence")
            continue
        # A single record can map to overlapping labels (e.g. bar + food).
        # Count its type-level support once per candidate, not once per label.
        type_record_weights = {
            analysis.record_id: analysis.emotion_intensity * 0.5
            for analysis, _ in type_records
        }
        type_weight = min(1.5, sum(type_record_weights.values()))
        feature_by_record: dict[int, float] = {}
        for analysis, facet in matched:
            feature_by_record[analysis.record_id] = max(
                feature_by_record.get(analysis.record_id, 0.0),
                analysis.emotion_intensity * facet.confidence,
            )
        feature_weight = sum(feature_by_record.values())
        matches = list(dict.fromkeys(term for _, term in verified))
        if not matches and type_records:
            matches = list(dict.fromkeys(
                type_support_by_record[analysis.record_id][0].target_text
                for analysis, _ in type_records
            ))
        evidence_level = "A" if matched else "B"
        diagnostics.decision("personalization_gate", place.kakao_place_id, "accepted", f"grade_{evidence_level}")
        category_affinity_weight = 0.0
        if category_affinity is not None:
            affinity_category, affinity_records, distinct_targets, _ = category_affinity
            category_affinity_weight = sum(item.emotion_intensity for item in affinity_records.values())
        score = (min(1.0, 0.55 + min(0.35, feature_weight * 0.12)
                      + min(0.10, len(feature_by_record) * 0.025))
                 if matched else min(0.45, 0.32 + type_weight * 0.08)
                 if type_records else min(0.34, 0.20 + min(0.10, category_affinity_weight * 0.012)
                                          + min(0.03, distinct_targets * 0.01)))
        place_label = place.place_name[:36]
        if matched:
            # Candidate-side claims are limited to exact, linked, confirmed
            # evidence. The remembered preference itself comes from the record.
            matched_facets = [facet for _, facet in matched]
            kind = matched_facets[0].target_kind.value
            if (RecommendationCategory.NATURE in place_categories
                    and any(RecommendationCategory.NATURE in facet.categories for facet in matched_facets)):
                kind = "nature"
            reason = _natural_personalized_reason(matches[0], place_label, kind)
        elif type_records:
            type_facet, supported_type_category, place_type = type_support_by_record[
                type_records[0][0].record_id
            ]
            if supported_type_category == RecommendationCategory.NATURE:
                reason = _natural_personalized_reason(
                    type_facet.target_text, place_label, "nature", place_type,
                )
            else:
                reason = _category_type_reason(type_facet.target_text, place_label, place_type)
        else:
            reason = (f"{label(affinity_category)} 분야에 좋은 경험을 여러 번 남기셨네요. "
                      f"{place_label}도 한번 둘러보는 건 어때요?")
        diagnostics.personalization_result(
            place.kakao_place_id,
            categories=[value.value for value in place_categories],
            positive_category_present=True, linkable_facet_count=len(facets),
            matched_facet_count=len(matched),
            type_evidence_accepted=bool(type_records or category_affinity),
            result=f"grade_{evidence_level}",
            reason=("repeated_positive_category_affinity" if not matched and not type_records else
                    "nature_type_evidence_accepted" if not matched and type_records
                    and type_records[0][1] == RecommendationCategory.NATURE else
                    "specific_category_type_evidence_accepted" if not matched else
                    "verified_same_record_feature"),
            category_affinity_record_count=(len(affinity_records) if category_affinity else 0),
            category_affinity_distinct_target_count=(distinct_targets if category_affinity else 0),
        )
        _log_place_decision(pipeline=_CATEGORY_PIPELINE_VERSION, stage="personalized_relevance_gate",
            kakao_place_id=place.kakao_place_id, place_name=place.place_name,
            category_name=place.category_name, category_group_code=place.category_group_code,
            category_status=item.classification.status.value, decision="accepted", reason=f"personalized_evidence_{evidence_level}")
        diversity_terms = (matches if matches else
                           [type_support_by_record[analysis.record_id][0].target_text
                            for analysis, _ in type_records] if type_records else
                           [f"category:{affinity_category.value}"])
        ranked.append((score, item.search_query_priority, place.place_name.casefold(), item, matches,
                       reason, evidence_level, feature_weight, type_weight,
                       len(type_records), len(type_record_weights), diversity_terms))
    logger.info(
        "AI_RECOMMENDATION_EVIDENCE_LINK category=%s confirmed_evidence_count=%d "
        "same_record_evidence_count=%d linked_facet_evidence_count=%d "
        "unlinked_confirmed_evidence_count=%d",
        category.value, confirmed_evidence_count, same_record_evidence_count,
        linked_facet_evidence_count, max(0, confirmed_evidence_count - linked_facet_evidence_count),
    )
    # Evidence-backed score stays primary. For near ties on the first page,
    # prefer coverage of a distinct verified preference instead of repeating
    # several venues tied to the same item. This is a tie-break, not a category quota.
    ranked.sort(key=lambda row: (-row[0], -row[1], row[2]))
    if len(ranked) > _PAGE_SIZE:
        remaining = list(ranked)
        diversified = [remaining.pop(0)]
        while remaining and len(diversified) < _PAGE_SIZE:
            covered = {term for row in diversified for term in row[11]}
            best_score = remaining[0][0]
            alternatives = [row for row in remaining
                            if row[0] >= best_score - 0.04
                            and set(row[11]).difference(covered)]
            choice = max(alternatives, key=lambda row: (len(set(row[11]).difference(covered)),
                                                        row[0], row[1], row[2]), default=remaining[0])
            diversified.append(choice)
            remaining.remove(choice)
        ranked = diversified + remaining
    output = []
    for (score, search_query_priority, _, item, matches, reason, level, feature_weight, type_weight,
         type_category_match_count, type_support_record_count, _) in ranked[:_MAX_POOL_SIZE]:
        place = item.place
        logger.info("AI_RECOMMENDATION_RANK rank=%d kakao_place_id=%s place_name=%r categories=%s evidence_level=%s score=%.4f feature_support=%.4f type_support=%.4f type_category_match_count=%d type_support_record_count=%d matched_term_count=%d search_query_priority=%d",
            len(output) + 1, place.kakao_place_id, " ".join(place.place_name.split())[:120],
            ",".join(value.value for value in item.classification.categories), level, score, feature_weight,
            type_weight, type_category_match_count, type_support_record_count, len(matches), search_query_priority)
        output.append(RecommendedPlace(rank=len(output) + 1, kakao_place_id=place.kakao_place_id,
            name=place.place_name, address=place.address, latitude=place.latitude, longitude=place.longitude,
            match_score=score, matched_keywords=matches, reason=reason[:180], source_url=place.place_url))
    evidence_distribution = {
        level: sum(row[6] == level for row in ranked)
        for level in ("A", "B")
    }
    evidence_distribution["C_excluded"] = category_only_excluded
    for level in ("A", "B"):
        diagnostics.add_count(f"eligible_grade_{level}", evidence_distribution[level])
    diagnostics.add_count("excluded_grade_C", category_only_excluded)
    diagnostics.add_count("ranking_input_candidates", len(search_result.candidates))
    logger.info(
        "AI_RECOMMENDATION_RANKING ranking_input_count=%d personalized_candidates_count=%d "
        "evidence_level_distribution=%s ranking_output_count=%d fallback_used=0",
        len(search_result.candidates), len(ranked), evidence_distribution, len(output),
    )
    diagnostics.stage("personalized_ranking", int((time.perf_counter() - ranking_started) * 1000))
    return output

def _log_place_decision(*, pipeline: str, stage: str, kakao_place_id: str | None,
                        place_name: str, category_name: str | None,
                        category_group_code: str | None = None,
                        decision: str, reason: str, category_status: str = "not_evaluated") -> None:
    """Log public POI identifiers and decision codes, never record/user/provider data."""
    safe_name = " ".join((place_name or "").split())[:120]
    safe_category = " ".join((category_name or "").split())[:160]
    logger.info(
        "AI recommendation candidate pipeline=%s stage=%s kakao_place_id=%s place_name=%r "
        "category_group_code=%s kakao_category=%r category_status=%s decision=%s reason=%s",
        pipeline, stage, kakao_place_id or "missing", safe_name,
        category_group_code or "unavailable", safe_category or "unavailable",
        category_status, decision, reason,
    )


def router(
    current_user,
    *,
    adapter=None,
    preference_service=None,
    search_service=None,
    verification_service=None,
    recommendation_service=None,
    image_service=None,
    candidate_search_service=None,
    preference_analysis_service=None,
    use_legacy_recommendation_pipeline=False,
):
    api = APIRouter(tags=["AI recommendations"])
    adapter = adapter or RecordRecommendationAdapter()
    # Decide before constructing default legacy collaborators: their defaults
    # must not make the legacy path look explicitly injected.
    legacy_collaborators_injected = any(
        service is not None
        for service in (preference_service, search_service, verification_service, recommendation_service)
    )
    use_category_pipeline = candidate_search_service is not None or not (
        use_legacy_recommendation_pipeline or legacy_collaborators_injected
    )
    image_service = image_service or RecommendationImageService()
    if use_category_pipeline:
        candidate_search_service = candidate_search_service or PlaceCandidateSearchService()
        preference_analysis_service = preference_analysis_service or RecordPreferenceAnalysisService()
    else:
        preference_service = preference_service or build_preference_service(LLM_PROVIDER)
        search_service = search_service or build_search_service(SEARCH_PROVIDER)
        verification_service = verification_service or KakaoPlaceVerificationService()
        recommendation_service = recommendation_service or build_recommendation_service(LLM_PROVIDER)
    # Short-lived process-local sessions avoid repeating provider calls while
    # the user's records and preferences remain unchanged. The key includes
    # both the authenticated user and a fingerprint of positive-record input.
    sessions: OrderedDict[tuple[int, str], dict] = OrderedDict()
    # Record analysis is category/region independent. Reuse its bounded result
    # across category switches so each selection does not trigger another LLM call.
    analysis_cache: OrderedDict[tuple[int, str], dict] = OrderedDict()

    @api.get("/ai/recommendations", response_model=PlaceRecommendationResponse)
    def recommendations(
        exclude_place_ids: str | None = None,
        previous_place_ids: str | None = None,
        refresh: bool = False,
        category: RecommendationCategory = RecommendationCategory.ALL,
        region: str | None = Query(default=None, min_length=1, max_length=100),
        user=Depends(current_user),
        db: Session = Depends(require_db),
    ):
        # Keep accepting the legacy query parameter for older clients, but
        # recommendation results are now always ranked across the full profile.
        requested_category = category
        category = RecommendationCategory.ALL
        diagnostics.set_user(int(user.id))
        diagnostics.set_value("category", category.value)
        diagnostics.set_value("region_explicit", bool(region))
        if requested_category != RecommendationCategory.ALL:
            logger.info("AI_RECOMMENDATION_DIAGNOSTIC event=legacy_category_ignored requested_category=%s",
                        requested_category.value)
        record_read_started = time.perf_counter()
        records = adapter.list_positive_records(db, user.id)
        visited_ids, visited_names = adapter.list_visited_places(db, user.id)
        # Authentication and record lookup share the request Session. The
        # recommendation records are detached DTOs, so release the read-only
        # transaction before calling OpenRouter, Tavily, or Kakao.
        db.rollback()
        diagnostics.set_value("record_count", len(records))
        diagnostics.add_count("visited_place_count", len(visited_ids) + len(visited_names))
        diagnostics.stage("record_db_read", int((time.perf_counter() - record_read_started) * 1000))
        logger.info("AI_RECOMMENDATION_TIMING stage=record_db_read elapsed_ms=%d record_count=%d",
                    int((time.perf_counter() - record_read_started) * 1000), len(records))
        pipeline_version = _CATEGORY_PIPELINE_VERSION if use_category_pipeline else _LEGACY_PIPELINE_VERSION
        logger.info(
            "AI_RECOMMENDATION_DIAGNOSTIC event=request pipeline=%s category=%s "
            "recommendation_session_cache_hit=pending record_preference_analysis_invoked=pending "
            "kakao_first_candidate_search_invoked=pending",
            pipeline_version, category.value,
        )
        _log_diagnostic("positive_records_count", len(records))
        if not records:
            _log_diagnostic("extracted_keywords_count", 0)
            _log_diagnostic("tavily_candidates_count", 0)
            _log_diagnostic("kakao_verified_candidates_count", 0)
            _log_diagnostic("qualified_candidates_count", 0)
            _log_diagnostic("ranking_service_output_count", 0)
            _log_diagnostic("validated_recommendations_count", 0)
            _log_diagnostic("final_response_count", 0)
            diagnostics.set_value("record_count", 0)
            diagnostics.add_count("final_recommendations", 0)
            diagnostics.set_value("session_status", "empty")
            return PlaceRecommendationResponse(session_status="empty")
        region_was_explicit = bool(region)
        selected_region = (region or _infer_region(records)) if use_category_pipeline else None
        if use_category_pipeline and not selected_region:
            raise HTTPException(422, "추천 지역을 지정해 주세요.")
        key_fingerprint = _records_fingerprint(records)
        visited_fingerprint = hashlib.sha256(json.dumps(
            [sorted(visited_ids), sorted(visited_names)], ensure_ascii=False,
            separators=(",", ":"),
        ).encode("utf-8")).hexdigest()
        session_fingerprint = (
            f"{key_fingerprint}:{visited_fingerprint}:{selected_region or ''}:v5"
            if use_category_pipeline else key_fingerprint
        )
        key = (int(user.id), session_fingerprint)
        now = time.monotonic()
        for old_key, session in list(sessions.items()):
            old_records_fingerprint = session.get("record_fingerprint", old_key[1])
            if now - session["created_at"] > _SESSION_TTL_SECONDS or (
                old_key[0] == key[0] and old_records_fingerprint != key_fingerprint
            ):
                sessions.pop(old_key, None)

        empty_retry_state = {"empty_retry_count": 0, "last_empty_retry_at": now}
        cached_session = sessions.get(key)
        if refresh and cached_session is not None and not cached_session.get("recommendations"):
            can_retry, empty_retry_state = _empty_session_retry_state(cached_session, now)
            if can_retry:
                # One explicit retry after cooldown may search again, reusing
                # the user-scoped record analysis cache. Repeated taps cannot
                # create an unbounded paid-provider loop.
                sessions.pop(key, None)

        if _invalidate_empty_session(sessions, key):
            # A previous release could persist a session after ranking
            # filtered every item out. Never serve that failure-shaped entry.
            _log_diagnostic("empty_recommendation_session_invalidated", 1)
        session = sessions.get(key)
        if session is not None:
            sessions.move_to_end(key)
            _log_diagnostic("recommendation_session_cache_hit", 1)
            diagnostics.set_value("cache_hit", True)
            diagnostics.add_count("session_cache_hit")
            logger.info(
                "AI_RECOMMENDATION_DIAGNOSTIC event=session pipeline=%s category=%s "
                "recommendation_session_cache_hit=1 record_preference_analysis_invoked=0 "
                "kakao_first_candidate_search_invoked=0",
                pipeline_version, category.value,
            )
            pool = session["recommendations"]
            first = session["first"]
            diagnostics.add_count("session_pool_candidates", len(pool))
            if not refresh:
                page = first
                session["shown_ids"] = {item.kakao_place_id for item in first if item.kakao_place_id}
            else:
                remaining = [item for item in pool if item.kakao_place_id not in session["shown_ids"]]
                if remaining:
                    page = remaining[:_PAGE_SIZE]
                    session["shown_ids"].update(item.kakao_place_id for item in page if item.kakao_place_id)
                else:
                    # Never label an already shown place as a fresh result.
                    # An exhausted session is stable and does not trigger
                    # unbounded paid-provider calls on repeated taps.
                    page = []
                    _log_diagnostic("recommendation_session_exhausted", 1)
            status = "available" if page else ("exhausted" if pool else "empty")
            diagnostics.add_count("session_remaining_candidates", sum(
                item.kakao_place_id not in session["shown_ids"] for item in pool if item.kakao_place_id
            ))
            result = PlaceRecommendationResponse(recommendations=page, session_status=status)
            _log_diagnostic("final_response_count", len(result.recommendations))
            diagnostics.add_count("final_recommendations", len(result.recommendations))
            diagnostics.set_value("session_status", status)
            logger.info(
                "AI_RECOMMENDATION_DIAGNOSTIC event=final_response pipeline=%s category=%s "
                "recommendation_session_cache_hit=1 final_response_count=%d final_recommendation_count=%d",
                pipeline_version, category.value, len(result.recommendations), len(result.recommendations),
            )
            try:
                image_started = time.perf_counter()
                enriched_result = image_service.enrich(db, user.id, result)
                diagnostics.stage("image_enrichment", int((time.perf_counter() - image_started) * 1000))
                return enriched_result
            except Exception as exc:
                logger.info("AI recommendation image enrichment skipped exception=%s", type(exc).__name__)
                return result

        if use_category_pipeline:
            _log_diagnostic("recommendation_session_cache_hit", 0)
            diagnostics.set_value("cache_hit", False)
            analysis_key = (int(user.id), key_fingerprint)
            cached_analysis = analysis_cache.get(analysis_key)
            cached_analysis_is_usable, cache_reason = _analysis_cache_decision(
                cached_analysis["analyses"] if cached_analysis else None
            )
            if cached_analysis and not cached_analysis_is_usable:
                analysis_cache.pop(analysis_key, None)
                logger.info("AI_RECOMMENDATION_DIAGNOSTIC event=record_analysis_cache_bypass reason=%s", cache_reason)
            if cached_analysis_is_usable and now - cached_analysis["created_at"] <= _SESSION_TTL_SECONDS:
                analysis_cache.move_to_end(analysis_key)
                all_analyses = cached_analysis["analyses"]
                _log_diagnostic("record_analysis_cache_hit", 1)
                diagnostics.add_count("analysis_cache_hit")
                analysis_invoked = 0
            else:
                _log_diagnostic("record_analysis_cache_hit", 0)
                diagnostics.set_flag("llm_analysis_invoked")
                analysis_invoked = 1
                analysis_started = time.perf_counter()
                all_analyses = preference_analysis_service.analyze(
                    records, category=RecommendationCategory.ALL
                )
                analysis_elapsed_ms = int((time.perf_counter() - analysis_started) * 1000)
                diagnostics.stage("preference_analysis", analysis_elapsed_ms)
                cache_eligible, cache_reason = _analysis_cache_decision(all_analyses)
                logger.info("AI_RECOMMENDATION_TIMING stage=record_preference_analysis elapsed_ms=%d "
                            "record_count=%d provider_usable_count=%d cache_eligible=%d cache_reason=%s",
                            analysis_elapsed_ms, len(records),
                            sum(item.evidence_status != EvidenceStatus.UNAVAILABLE for item in all_analyses.analyses),
                            int(cache_eligible), cache_reason)
                if cache_eligible:
                    analysis_cache[analysis_key] = {
                        "created_at": now,
                        "analyses": all_analyses,
                    }
                    analysis_cache.move_to_end(analysis_key)
                    while len(analysis_cache) > 128:
                        analysis_cache.popitem(last=False)
            analyses = all_analyses
            diagnostics.add_count("analysis_records", len(analyses.analyses))
            diagnostics.add_count("analysis_success_records", sum(item.evidence_status != EvidenceStatus.UNAVAILABLE for item in analyses.analyses))
            diagnostics.add_count("analysis_failed_records", sum(item.evidence_status == EvidenceStatus.UNAVAILABLE for item in analyses.analyses))
            diagnostics.add_count("preference_facets", sum(len(item.facets) for item in analyses.analyses))
            _log_diagnostic("record_preference_analyses_count", len(analyses.analyses))
            preference_distribution = {
                value.value: sum(value in analysis.categories for analysis in analyses.analyses)
                for value in RecommendationCategory if value != RecommendationCategory.ALL
            }
            unknown_category_count = sum(
                not any(value != RecommendationCategory.ALL for value in analysis.categories)
                for analysis in analyses.analyses
            )
            unknown_place_type_count = sum(
                analysis.place_type == PlaceType.UNKNOWN for analysis in analyses.analyses
            )
            logger.info(
                "AI_RECOMMENDATION_DIAGNOSTIC event=preference_profile positive_records_count=%d "
                "preference_category_distribution=%s unknown_category_count=%d unknown_place_type_count=%d",
                len(records), ",".join(f"{key}={value}" for key, value in preference_distribution.items()),
                unknown_category_count, unknown_place_type_count,
            )
            selected_categories = sorted({
                item.value
                for analysis in analyses.analyses
                for item in analysis.categories
                if item != RecommendationCategory.ALL
            })
            logger.info(
                "AI_RECOMMENDATION_DIAGNOSTIC event=analysis pipeline=%s category=%s "
                "recommendation_session_cache_hit=0 record_preference_analysis_invoked=%d "
                "kakao_first_candidate_search_invoked=pending selected_preference_categories=%s",
                pipeline_version, category.value, analysis_invoked,
                ",".join(selected_categories) or "none",
            )
            diagnostics.add_count("preference_unknown_category_records", unknown_category_count)
            for preference_category, count in preference_distribution.items():
                diagnostics.add_count(f"preference_category_{preference_category}", count)
            for preference_category in RecommendationCategory:
                if preference_category != RecommendationCategory.ALL:
                    diagnostics.add_count(
                        f"preference_facets_category_{preference_category.value}",
                        sum(preference_category in facet.categories
                            for analysis in analyses.analyses for facet in analysis.facets),
                    )
            initial_kakao_budget = min(
                getattr(candidate_search_service, "MAX_KAKAO_CALLS", PlaceCandidateSearchService.MAX_KAKAO_CALLS),
                getattr(candidate_search_service, "INITIAL_KAKAO_CALLS", PlaceCandidateSearchService.INITIAL_KAKAO_CALLS),
            )
            initial_tavily_budget = min(
                getattr(candidate_search_service, "MAX_TAVILY_CALLS", PlaceCandidateSearchService.MAX_TAVILY_CALLS),
                getattr(candidate_search_service, "INITIAL_TAVILY_CALLS", PlaceCandidateSearchService.INITIAL_TAVILY_CALLS),
            )
            initial_tavily_candidate_budget = min(
                getattr(candidate_search_service, "MAX_TAVILY_CANDIDATES", PlaceCandidateSearchService.MAX_TAVILY_CANDIDATES),
                getattr(candidate_search_service, "INITIAL_TAVILY_CANDIDATES", PlaceCandidateSearchService.INITIAL_TAVILY_CANDIDATES),
            )
            try:
                logger.info(
                    "AI_RECOMMENDATION_DIAGNOSTIC event=kakao_search pipeline=%s category=%s "
                    "recommendation_session_cache_hit=0 record_preference_analysis_invoked=%d "
                    "kakao_first_candidate_search_invoked=1",
                    pipeline_version, category.value, analysis_invoked,
                )
                search_started = time.perf_counter()
                search_result = candidate_search_service.search(
                    category=category,
                    region=selected_region,
                    preferences=analyses.analyses,
                    visited_place_ids=visited_ids,
                    visited_place_names=visited_names,
                    allow_region_expansion=not region_was_explicit,
                    query_offset=0,
                    kakao_call_budget=initial_kakao_budget,
                    tavily_call_budget=initial_tavily_budget,
                    tavily_candidate_budget=initial_tavily_candidate_budget,
                )
                logger.info("AI_RECOMMENDATION_TIMING stage=place_candidate_search elapsed_ms=%d "
                            "kakao_calls=%d tavily_calls=%d",
                            int((time.perf_counter() - search_started) * 1000),
                            search_result.kakao_call_count, search_result.tavily_call_count)
                diagnostics.stage("candidate_search_initial", int((time.perf_counter() - search_started) * 1000))
            except (ValueError, TypeError) as exc:
                raise HTTPException(422, "추천 분야 또는 지역을 확인해 주세요.") from exc
            if search_result.search_skip_reason == "no_supported_preference_query" and any(
                item.evidence_status == EvidenceStatus.UNAVAILABLE for item in all_analyses.analyses
            ):
                logger.error(
                    "AI_RECOMMENDATION_DIAGNOSTIC event=search_unavailable pipeline=%s category=%s "
                    "reason=analysis_unavailable_without_safe_search_input",
                    pipeline_version, category.value,
                )
                raise HTTPException(503, "\uCDE8\uD5A5 \uBD84\uC11D\uC5D0 \uC2E4\uD328\uD574 \uC548\uC804\uD55C \uAC80\uC0C9 \uC870\uAC74\uC744 \uB9CC\uB4E4 \uC218 \uC5C6\uC2B5\uB2C8\uB2E4.")
            _log_diagnostic("kakao_candidate_count", len(search_result.candidates))
            category_verified_count = sum(
                item.classification.status == CategoryMatchStatus.CONFIRMED
                for item in search_result.candidates
            )
            candidate_category_counts = {
                value.value: sum(value in item.classification.categories for item in search_result.candidates)
                for value in RecommendationCategory if value != RecommendationCategory.ALL
            }
            logger.info(
                "AI_RECOMMENDATION_DIAGNOSTIC event=category_candidates pipeline=%s category=%s "
                "kakao_category_verified_count=%d category_unconfirmed_returned_count=%d candidate_count_by_category=%s",
                pipeline_version, category.value, category_verified_count,
                len(search_result.candidates) - category_verified_count,
                ",".join(f"{key}={value}" for key, value in candidate_category_counts.items()),
            )
            tavily_evidence_confirmed_count = sum(
                evidence.status == FeatureEvidenceStatus.CONFIRMED
                for item in search_result.candidates for evidence in item.preference_evidence
            )
            _log_diagnostic("tavily_evidence_confirmed_count", tavily_evidence_confirmed_count)
            if search_result.kakao_status == ProviderStatus.UNAVAILABLE:
                raise HTTPException(503, "Kakao 장소 검색을 사용할 수 없습니다.")
            recommendations = _build_category_recommendations(search_result, analyses, category)
            if len(recommendations) < _PAGE_SIZE and search_result.query_count >= initial_kakao_budget:
                continuation_started = time.perf_counter()
                continuation_kakao_budget = max(
                    0, getattr(candidate_search_service, "MAX_KAKAO_CALLS", PlaceCandidateSearchService.MAX_KAKAO_CALLS)
                    - initial_kakao_budget,
                )
                continuation_tavily_budget = max(
                    0, getattr(candidate_search_service, "MAX_TAVILY_CALLS", PlaceCandidateSearchService.MAX_TAVILY_CALLS)
                    - initial_tavily_budget,
                )
                continuation_tavily_candidates = max(
                    0, getattr(candidate_search_service, "MAX_TAVILY_CANDIDATES", PlaceCandidateSearchService.MAX_TAVILY_CANDIDATES)
                    - initial_tavily_candidate_budget,
                )
                continuation = candidate_search_service.search(
                    category=category,
                    region=selected_region,
                    preferences=analyses.analyses,
                    visited_place_ids=visited_ids,
                    visited_place_names=visited_names,
                    allow_region_expansion=not region_was_explicit,
                    query_offset=initial_kakao_budget,
                    kakao_call_budget=continuation_kakao_budget,
                    tavily_call_budget=continuation_tavily_budget,
                    tavily_candidate_budget=continuation_tavily_candidates,
                )
                diagnostics.stage("candidate_search_continuation", int((time.perf_counter() - continuation_started) * 1000))
                merged_candidates = []
                seen_candidate_ids = set()
                for candidate in [*search_result.candidates, *continuation.candidates]:
                    candidate_id = candidate.place.kakao_place_id
                    if candidate_id in seen_candidate_ids:
                        continue
                    seen_candidate_ids.add(candidate_id)
                    merged_candidates.append(candidate)
                search_result = search_result.model_copy(update={
                    "candidates": merged_candidates[:getattr(candidate_search_service, "MAX_CANDIDATES", PlaceCandidateSearchService.MAX_CANDIDATES)],
                    "kakao_call_count": min(getattr(candidate_search_service, "MAX_KAKAO_CALLS", PlaceCandidateSearchService.MAX_KAKAO_CALLS),
                                            search_result.kakao_call_count + continuation.kakao_call_count),
                    "tavily_call_count": min(getattr(candidate_search_service, "MAX_TAVILY_CALLS", PlaceCandidateSearchService.MAX_TAVILY_CALLS),
                                             search_result.tavily_call_count + continuation.tavily_call_count),
                    "query_count": min(getattr(candidate_search_service, "MAX_KAKAO_CALLS", PlaceCandidateSearchService.MAX_KAKAO_CALLS),
                                        search_result.query_count + continuation.query_count),
                    "kakao_cache_hit_count": min(getattr(candidate_search_service, "MAX_KAKAO_CALLS", PlaceCandidateSearchService.MAX_KAKAO_CALLS),
                                                  search_result.kakao_cache_hit_count + continuation.kakao_cache_hit_count),
                    "kakao_empty_cache_hit_count": min(getattr(candidate_search_service, "MAX_KAKAO_CALLS", PlaceCandidateSearchService.MAX_KAKAO_CALLS),
                                                        search_result.kakao_empty_cache_hit_count + continuation.kakao_empty_cache_hit_count),
                })
                recommendations = _build_category_recommendations(search_result, analyses, category)
                logger.info(
                    "AI_RECOMMENDATION_SEARCH_STAGE stage=continuation kakao_calls=%d tavily_calls=%d "
                    "candidate_count=%d eligible_recommendation_count=%d elapsed_ms=%d",
                    continuation.kakao_call_count, continuation.tavily_call_count,
                    len(continuation.candidates), len(recommendations),
                    int((time.perf_counter() - continuation_started) * 1000),
                )
            if not recommendations:
                sessions[key] = {
                    "created_at": now,
                    "record_fingerprint": key_fingerprint,
                    "recommendations": [],
                    "first": [],
                    "shown_ids": set(),
                    "empty_complete": True,
                    **empty_retry_state,
                }
                sessions.move_to_end(key)
                while len(sessions) > 128:
                    sessions.popitem(last=False)
                _log_diagnostic("final_response_count", 0)
                diagnostics.add_count("final_recommendations", 0)
                diagnostics.set_value("session_status", "empty")
                _log_diagnostic("empty_recommendation_session_saved", 1)
                diagnostics.add_count("session_pool_candidates", 0)
                logger.info(
                    "AI_RECOMMENDATION_DIAGNOSTIC event=final_response pipeline=%s category=%s "
                    "recommendation_session_cache_hit=0 empty_session_saved=1 record_preference_analysis_invoked=%d "
                    "kakao_first_candidate_search_invoked=1 final_response_count=0 final_recommendation_count=0",
                    pipeline_version, category.value, analysis_invoked,
                )
                return PlaceRecommendationResponse(session_status="empty")
            first = recommendations[:_PAGE_SIZE]
            diagnostics.add_count("session_pool_candidates", len(recommendations))
            diagnostics.add_count("session_remaining_candidates", max(0, len(recommendations) - len(first)))
            sessions[key] = {
                "created_at": now,
                "record_fingerprint": key_fingerprint,
                "recommendations": recommendations,
                "first": first,
                "shown_ids": {item.kakao_place_id for item in first if item.kakao_place_id},
            }
            sessions.move_to_end(key)
            while len(sessions) > 128:
                sessions.popitem(last=False)
            result = PlaceRecommendationResponse(recommendations=first)
            _log_diagnostic("final_response_count", len(first))
            diagnostics.add_count("final_recommendations", len(first))
            diagnostics.set_value("session_status", "available")
            logger.info(
                "AI_RECOMMENDATION_DIAGNOSTIC event=final_response pipeline=%s category=%s "
                "recommendation_session_cache_hit=0 record_preference_analysis_invoked=%d "
                "kakao_first_candidate_search_invoked=1 final_response_count=%d final_recommendation_count=%d",
                pipeline_version, category.value, analysis_invoked, len(first), len(first),
            )
            try:
                image_started = time.perf_counter()
                enriched_result = image_service.enrich(db, user.id, result)
                diagnostics.stage("image_enrichment", int((time.perf_counter() - image_started) * 1000))
                return enriched_result
            except Exception as exc:
                logger.info("AI recommendation image enrichment skipped exception=%s", type(exc).__name__)
                return result


        # A new or changed record fingerprint starts a new session. Legacy ID
        # query parameters are intentionally ignored: excluding places before
        # suitability evaluation previously promoted weaker candidates.
        try:
            _log_diagnostic("recommendation_session_cache_hit", 0)
            logger.info(
                "AI_RECOMMENDATION_DIAGNOSTIC event=legacy_pipeline pipeline=%s category=%s "
                "recommendation_session_cache_hit=0 record_preference_analysis_invoked=0 "
                "kakao_first_candidate_search_invoked=0 selected_preference_categories=not_available",
                pipeline_version, category.value,
            )
            keywords = preference_service.extract_keywords(records)
        except AIConfigurationError as exc:
            raise HTTPException(503, "AI recommendation provider is not configured") from exc
        except AIRecommendationError as exc:
            _log_provider_failure("openrouter_keyword_extraction", exc)
            raise HTTPException(502, "AI recommendation provider request failed") from exc
        _log_diagnostic("extracted_keywords_count", len(keywords.keywords))
        try:
            if not keywords.keywords:
                _log_diagnostic("tavily_candidates_count", 0)
                _log_diagnostic("kakao_verified_candidates_count", 0)
                _log_diagnostic("qualified_candidates_count", 0)
                _log_diagnostic("ranking_service_output_count", 0)
                _log_diagnostic("validated_recommendations_count", 0)
                _log_diagnostic("final_response_count", 0)
                return PlaceRecommendationResponse()
            candidates = search_service.search_candidates(keywords.keywords, records)
        except AIConfigurationError as exc:
            raise HTTPException(503, "AI recommendation provider is not configured") from exc
        except AIRecommendationError as exc:
            _log_provider_failure("tavily_place_search", exc)
            raise HTTPException(502, "AI recommendation provider request failed") from exc
        _log_diagnostic("tavily_candidates_count", len(candidates.candidates))
        try:
            candidates = verification_service.verify(candidates, keywords.keywords, records)
        except AIConfigurationError as exc:
            raise HTTPException(503, "AI recommendation provider is not configured") from exc
        except AIRecommendationError as exc:
            _log_provider_failure("kakao_place_verification", exc)
            raise HTTPException(502, "AI recommendation provider request failed") from exc
        _log_diagnostic("kakao_verified_candidates_count", len(candidates.candidates))
        eligible = _filter_suitable_candidates(candidates.candidates, keywords.keywords)
        eligible_ids = {candidate.kakao_place_id for candidate in eligible}
        for candidate in candidates.candidates:
            accepted = candidate.kakao_place_id in eligible_ids
            _log_place_decision(
                pipeline=_LEGACY_PIPELINE_VERSION,
                stage="legacy_preference_suitability",
                kakao_place_id=candidate.kakao_place_id,
                place_name=candidate.name,
                category_name=None,
                category_status="not_evaluated",
                decision="accepted" if accepted else "rejected",
                reason="legacy_preference_score_passed" if accepted else "legacy_preference_score_or_fields_failed",
            )
        _log_diagnostic("suitability_rejected_candidates_count", len(candidates.candidates) - len(eligible))
        _log_diagnostic("suitable_verified_candidates_count", len(eligible))
        _log_diagnostic("qualified_candidates_count", len(eligible))
        try:
            if not eligible:
                _log_diagnostic("ranking_service_output_count", 0)
                _log_diagnostic("validated_recommendations_count", 0)
                _log_diagnostic("final_response_count", 0)
                return PlaceRecommendationResponse()
            ranking_input = candidates.model_copy(update={"candidates": eligible[:_MAX_POOL_SIZE]})
            try:
                ranked = recommendation_service.recommend(records, keywords.keywords, ranking_input)
                ranking_output_count = len(ranked.recommendations)
            except (AIResponseError, InvalidRecommendationError) as exc:
                # Malformed/empty ranking is recoverable only from the candidates
                # that already passed deterministic evidence and Kakao checks.
                logger.warning("AI recommendation ranking fallback reason=%s", type(exc).__name__)
                ranked = PlaceRecommendationResponse()
                ranking_output_count = 0
            _log_diagnostic("ranking_service_output_count", ranking_output_count)
            evidence_by_id = {item.kakao_place_id: item for item in eligible}
            safe_ranked = []
            seen_ids = set()
            for item in ranked.recommendations:
                evidence = evidence_by_id.get(item.kakao_place_id)
                if evidence is None or item.kakao_place_id in seen_ids:
                    continue
                supported_terms = _supported_preference_terms(evidence, keywords.keywords)
                matched = [term for term in item.matched_keywords if term in supported_terms]
                if not matched:
                    continue
                seen_ids.add(item.kakao_place_id)
                safe_ranked.append(item.model_copy(update={"rank": len(safe_ranked) + 1, "matched_keywords": matched}))
            ranked = PlaceRecommendationResponse(recommendations=safe_ranked[:_MAX_POOL_SIZE])
            for place in ranked.recommendations:
                _log_place_decision(
                    pipeline=_LEGACY_PIPELINE_VERSION,
                    stage="legacy_final_response",
                    kakao_place_id=place.kakao_place_id,
                    place_name=place.name,
                    category_name=None,
                    category_status="not_evaluated",
                    decision="returned",
                    reason="legacy_rank_and_preference_evidence_passed",
                )
            _log_diagnostic("filtered_ranking_output_count", len(ranked.recommendations))
            _log_diagnostic(
                "ranking_validation_rejected_count",
                max(0, ranking_output_count - len(ranked.recommendations)),
            )
            if len(ranked.recommendations) < min(_PAGE_SIZE, len(eligible)):
                fallback_items = _fallback_recommendations(eligible, keywords.keywords)
                present = {item.kakao_place_id for item in ranked.recommendations}
                for item in fallback_items:
                    if item.kakao_place_id in present:
                        continue
                    ranked.recommendations.append(item.model_copy(update={"rank": len(ranked.recommendations) + 1}))
                    present.add(item.kakao_place_id)
                    if len(ranked.recommendations) >= _PAGE_SIZE:
                        break
                if fallback_items:
                    _log_diagnostic("evidence_fallback_recommendations_count", len(ranked.recommendations))
            first = ranked.recommendations[:_PAGE_SIZE]
            _log_diagnostic("ranked_suitable_pool_count", len(ranked.recommendations))
            if not ranked.recommendations:
                # Empty results are retryable diagnostics, not recommendation
                # sessions. Provider/API exceptions also exit before storage.
                _log_diagnostic("empty_recommendation_session_saved", 0)
                _log_diagnostic("final_response_count", 0)
                return PlaceRecommendationResponse()
            page = first
            sessions[key] = {
                "created_at": now,
                "record_fingerprint": key_fingerprint,
                "recommendations": ranked.recommendations,
                "first": first,
                "shown_ids": {item.kakao_place_id for item in first if item.kakao_place_id},
            }
            sessions.move_to_end(key)
            while len(sessions) > 128:
                sessions.popitem(last=False)
            result = PlaceRecommendationResponse(recommendations=page)
            _log_diagnostic("final_response_count", len(result.recommendations))
            logger.info(
                "AI_RECOMMENDATION_DIAGNOSTIC event=final_response pipeline=%s category=%s "
                "recommendation_session_cache_hit=0 record_preference_analysis_invoked=0 "
                "kakao_first_candidate_search_invoked=0 final_response_count=%d",
                pipeline_version, category.value, len(result.recommendations),
            )
            try:
                return image_service.enrich(db, user.id, result)
            except Exception as exc:
                logger.info("AI recommendation image enrichment skipped exception=%s", type(exc).__name__)
                return result
        except AIConfigurationError as exc:
            raise HTTPException(503, "AI recommendation provider is not configured") from exc
        except AIRecommendationError as exc:
            _log_provider_failure("openrouter_top3_ranking", exc)
            raise HTTPException(502, "AI recommendation provider request failed") from exc
    return api
