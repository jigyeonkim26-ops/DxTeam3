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
from .ai_recommendation_models import PlaceRecommendationResponse, RecommendedPlace
from .config import LLM_PROVIDER, SEARCH_PROVIDER
from .records import require_db
from .recommendation_record_adapter import RecordRecommendationAdapter
from .kakao_place_verification_service import KakaoPlaceVerificationService
from .provider_factory import build_preference_service, build_recommendation_service, build_search_service
from .recommendation_image_service import RecommendationImageService
from .place_candidate_search_service import (
    CategoryMatchStatus,
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
_CATEGORY_PIPELINE_VERSION = "category-v3"
_LEGACY_PIPELINE_VERSION = "legacy-tavily-v2"


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


def _invalidate_empty_session(sessions, key) -> bool:
    session = sessions.get(key)
    if session is None or session.get("recommendations"):
        return False
    sessions.pop(key, None)
    return True


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
            locality = " ".join(parts[:2])
            counts[locality] = counts.get(locality, 0) + 1
    return max(counts, key=counts.get) if counts else None


def _category_label(category: RecommendationCategory) -> str:
    return {
        RecommendationCategory.ALL: "확인된 분야",
        RecommendationCategory.FOOD: "음식점",
        RecommendationCategory.BAR: "술집",
        RecommendationCategory.CAFE: "카페",
        RecommendationCategory.NATURE: "자연·산책 장소",
        RecommendationCategory.ACTIVITY: "문화·스포츠 장소",
    }[category]


def _build_category_recommendations(search_result, analyses, category: RecommendationCategory):
    """Rank personalized A/B candidates; exclude category-only C."""
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
            _log_place_decision(pipeline=_CATEGORY_PIPELINE_VERSION, stage="final_category_gate",
                kakao_place_id=place.kakao_place_id, place_name=place.place_name,
                category_name=place.category_name, category_group_code=place.category_group_code,
                category_status=item.classification.status.value, decision="rejected", reason="category_not_confirmed")
            continue
        place_categories = set(item.classification.categories)
        facets = [(analysis, facet) for analysis in analyses.analyses for facet in analysis.facets
            if facet.polarity == "liked"
            and (category == RecommendationCategory.ALL or category in facet.categories)
            and (category == RecommendationCategory.ALL or category in analysis.categories)
            and place_categories.intersection(facet.categories)]
        type_records = [(analysis, value) for analysis in analyses.analyses
            for value in set(analysis.categories).intersection(place_categories)
            if value != RecommendationCategory.ALL
            and (category == RecommendationCategory.ALL or value == category)
            and (analysis.place_type != PlaceType.UNKNOWN or any(
                facet.polarity == "liked" and value in facet.categories for facet in analysis.facets
            ))]
        if not facets and not type_records:
            category_only_excluded += 1
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
        facet_type_weight = sum(analysis.emotion_intensity * facet.confidence for analysis, facet in facets)
        # A single record can map to overlapping labels (e.g. bar + food).
        # Count its type-level support once per candidate, not once per label.
        type_record_weights = {
            analysis.record_id: analysis.emotion_intensity * 0.5
            for analysis, _ in type_records
        }
        type_weight = max(facet_type_weight, sum(type_record_weights.values()))
        feature_weight = sum(analysis.emotion_intensity * facet.confidence for analysis, facet in matched)
        matches = list(dict.fromkeys(term for _, term in verified))
        evidence_level = "A" if matched else "B"
        score = (min(1.0, 0.55 + min(0.35, feature_weight * 0.12) + min(0.10, len(matched) * 0.025))
                 if matched else min(0.30, 0.10 + type_weight * 0.04))
        if matched:
            # These terms have confirmed, URL-backed candidate evidence.
            # Naming them keeps distinct candidates from receiving one generic reason.
            reason = f"\uC774\uC804\uC5D0 \uC88B\uC544\uD558\uC168\uB358 \u2018{', '.join(matches)}\u2019\uC5D0 \uAD00\uD55C \uC815\uBCF4\uAC00 \uD655\uC778\uB41C \uACF3\uC774\uC5D0\uC694."
        else:
            types = list(dict.fromkeys(label(value) for _, value in type_records if value in place_categories))
            type_label = ", ".join(types) or "\uC774 \uBD84\uC57C"
            reason = f"\uC774\uC804\uC5D0 {type_label}\uC5D0\uC11C\uC758 \uACBD\uD5D8\uC744 \uC88B\uC544\uD558\uC168\uB358 \uAE30\uB85D\uC744 \uBC14\uD0D5\uC73C\uB85C \uCD94\uCC9C\uD574\uC694."
        _log_place_decision(pipeline=_CATEGORY_PIPELINE_VERSION, stage="personalized_relevance_gate",
            kakao_place_id=place.kakao_place_id, place_name=place.place_name,
            category_name=place.category_name, category_group_code=place.category_group_code,
            category_status=item.classification.status.value, decision="accepted", reason=f"personalized_evidence_{evidence_level}")
        ranked.append((score, place.place_name.casefold(), item, matches, reason, evidence_level,
                       feature_weight, type_weight, len(type_records), len(type_record_weights)))
    logger.info(
        "AI_RECOMMENDATION_EVIDENCE_LINK category=%s confirmed_evidence_count=%d "
        "same_record_evidence_count=%d linked_facet_evidence_count=%d "
        "unlinked_confirmed_evidence_count=%d",
        category.value, confirmed_evidence_count, same_record_evidence_count,
        linked_facet_evidence_count, max(0, confirmed_evidence_count - linked_facet_evidence_count),
    )
    ranked.sort(key=lambda row: (-row[0], row[1]))
    output = []
    for (score, _, item, matches, reason, level, feature_weight, type_weight,
         type_category_match_count, type_support_record_count) in ranked[:_MAX_POOL_SIZE]:
        place = item.place
        logger.info("AI_RECOMMENDATION_RANK rank=%d kakao_place_id=%s place_name=%r categories=%s evidence_level=%s score=%.4f feature_support=%.4f type_support=%.4f type_category_match_count=%d type_support_record_count=%d matched_term_count=%d",
            len(output) + 1, place.kakao_place_id, " ".join(place.place_name.split())[:120],
            ",".join(value.value for value in item.classification.categories), level, score, feature_weight,
            type_weight, type_category_match_count, type_support_record_count, len(matches))
        output.append(RecommendedPlace(rank=len(output) + 1, kakao_place_id=place.kakao_place_id,
            name=place.place_name, address=place.address, latitude=place.latitude, longitude=place.longitude,
            match_score=score, matched_keywords=matches, reason=reason[:500], source_url=place.place_url))
    evidence_distribution = {
        level: sum(row[5] == level for row in ranked)
        for level in ("A", "B")
    }
    evidence_distribution["C_excluded"] = category_only_excluded
    logger.info(
        "AI_RECOMMENDATION_RANKING ranking_input_count=%d personalized_candidates_count=%d "
        "evidence_level_distribution=%s ranking_output_count=%d fallback_used=0",
        len(search_result.candidates), len(ranked), evidence_distribution, len(output),
    )
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
        records = adapter.list_positive_records(db, user.id)
        # Authentication and record lookup share the request Session. The
        # recommendation records are detached DTOs, so release the read-only
        # transaction before calling OpenRouter, Tavily, or Kakao.
        db.rollback()
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
            return PlaceRecommendationResponse()
        selected_region = (region or _infer_region(records)) if use_category_pipeline else None
        if use_category_pipeline and not selected_region:
            raise HTTPException(422, "추천 지역을 지정해 주세요.")
        key_fingerprint = _records_fingerprint(records)
        session_fingerprint = f"{key_fingerprint}:{category.value}:{selected_region or ''}:v3" if use_category_pipeline else key_fingerprint
        key = (int(user.id), session_fingerprint)
        now = time.monotonic()
        for old_key, session in list(sessions.items()):
            old_records_fingerprint = session.get("record_fingerprint", old_key[1])
            if now - session["created_at"] > _SESSION_TTL_SECONDS or (
                old_key[0] == key[0] and old_records_fingerprint != key_fingerprint
            ):
                sessions.pop(old_key, None)

        if _invalidate_empty_session(sessions, key):
            # A previous release could persist a session after ranking
            # filtered every item out. Never serve that failure-shaped entry.
            _log_diagnostic("empty_recommendation_session_invalidated", 1)
        session = sessions.get(key)
        if session is not None:
            sessions.move_to_end(key)
            _log_diagnostic("recommendation_session_cache_hit", 1)
            logger.info(
                "AI_RECOMMENDATION_DIAGNOSTIC event=session pipeline=%s category=%s "
                "recommendation_session_cache_hit=1 record_preference_analysis_invoked=0 "
                "kakao_first_candidate_search_invoked=0",
                pipeline_version, category.value,
            )
            pool = session["recommendations"]
            first = session["first"]
            if not refresh:
                page = first
                session["shown_ids"] = {item.kakao_place_id for item in first if item.kakao_place_id}
            else:
                remaining = [item for item in pool if item.kakao_place_id not in session["shown_ids"]]
                if remaining:
                    page = remaining[:_PAGE_SIZE]
                    session["shown_ids"].update(item.kakao_place_id for item in page if item.kakao_place_id)
                else:
                    # Once the suitable, ranked pool is exhausted, cycle back
                    # to the original recommendations in their original order.
                    page = first
                    session["shown_ids"] = {item.kakao_place_id for item in first if item.kakao_place_id}
            result = PlaceRecommendationResponse(recommendations=page)
            _log_diagnostic("final_response_count", len(result.recommendations))
            logger.info(
                "AI_RECOMMENDATION_DIAGNOSTIC event=final_response pipeline=%s category=%s "
                "recommendation_session_cache_hit=1 final_response_count=%d final_recommendation_count=%d",
                pipeline_version, category.value, len(result.recommendations), len(result.recommendations),
            )
            try:
                return image_service.enrich(db, user.id, result)
            except Exception as exc:
                logger.info("AI recommendation image enrichment skipped exception=%s", type(exc).__name__)
                return result

        if use_category_pipeline:
            _log_diagnostic("recommendation_session_cache_hit", 0)
            analysis_key = (int(user.id), key_fingerprint)
            cached_analysis = analysis_cache.get(analysis_key)
            cached_analysis_is_usable = bool(
                cached_analysis
                and not any(item.evidence_status == EvidenceStatus.UNAVAILABLE
                            for item in cached_analysis["analyses"].analyses)
            )
            if cached_analysis and not cached_analysis_is_usable:
                analysis_cache.pop(analysis_key, None)
                logger.info("AI_RECOMMENDATION_DIAGNOSTIC event=record_analysis_cache_bypass reason=previous_analysis_unavailable")
            if cached_analysis_is_usable and now - cached_analysis["created_at"] <= _SESSION_TTL_SECONDS:
                analysis_cache.move_to_end(analysis_key)
                all_analyses = cached_analysis["analyses"]
                _log_diagnostic("record_analysis_cache_hit", 1)
                analysis_invoked = 0
            else:
                _log_diagnostic("record_analysis_cache_hit", 0)
                analysis_invoked = 1
                all_analyses = preference_analysis_service.analyze(
                    records, category=RecommendationCategory.ALL
                )
                if not any(item.evidence_status == EvidenceStatus.UNAVAILABLE for item in all_analyses.analyses):
                    analysis_cache[analysis_key] = {
                        "created_at": now,
                        "analyses": all_analyses,
                    }
                    analysis_cache.move_to_end(analysis_key)
                    while len(analysis_cache) > 128:
                        analysis_cache.popitem(last=False)
            if category == RecommendationCategory.ALL:
                analyses = all_analyses
            else:
                scoped = []
                for analysis in all_analyses.analyses:
                    if category not in analysis.categories:
                        continue
                    scoped.append(analysis.model_copy(update={
                        "facets": [facet for facet in analysis.facets if category in facet.categories]
                    }))
                analyses = all_analyses.model_copy(update={"analyses": scoped})
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
            visited_ids = {record.kakao_place_id for record in records if record.kakao_place_id}
            visited_names = {record.place_name for record in records if record.place_name}
            try:
                logger.info(
                    "AI_RECOMMENDATION_DIAGNOSTIC event=kakao_search pipeline=%s category=%s "
                    "recommendation_session_cache_hit=0 record_preference_analysis_invoked=%d "
                    "kakao_first_candidate_search_invoked=1",
                    pipeline_version, category.value, analysis_invoked,
                )
                search_result = candidate_search_service.search(
                    category=category,
                    region=selected_region,
                    preferences=analyses.analyses,
                    visited_place_ids=visited_ids,
                    visited_place_names=visited_names,
                )
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
            if not recommendations:
                _log_diagnostic("final_response_count", 0)
                logger.info(
                    "AI_RECOMMENDATION_DIAGNOSTIC event=final_response pipeline=%s category=%s "
                    "recommendation_session_cache_hit=0 record_preference_analysis_invoked=%d "
                    "kakao_first_candidate_search_invoked=1 final_response_count=0 final_recommendation_count=0",
                    pipeline_version, category.value, analysis_invoked,
                )
                return PlaceRecommendationResponse()
            first = recommendations[:_PAGE_SIZE]
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
            logger.info(
                "AI_RECOMMENDATION_DIAGNOSTIC event=final_response pipeline=%s category=%s "
                "recommendation_session_cache_hit=0 record_preference_analysis_invoked=%d "
                "kakao_first_candidate_search_invoked=1 final_response_count=%d final_recommendation_count=%d",
                pipeline_version, category.value, analysis_invoked, len(first), len(first),
            )
            try:
                return image_service.enrich(db, user.id, result)
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
