"""Authenticated AI recommendation endpoint over existing database records."""

import logging

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from .ai_recommendation_errors import AIConfigurationError, AIRecommendationError
from .ai_recommendation_models import PlaceRecommendationResponse
from .config import LLM_PROVIDER, SEARCH_PROVIDER
from .records import require_db
from .recommendation_record_adapter import RecordRecommendationAdapter
from .kakao_place_verification_service import KakaoPlaceVerificationService
from .provider_factory import build_preference_service, build_recommendation_service, build_search_service
from .recommendation_image_service import RecommendationImageService

# Uvicorn configures this logger with its console error handler.
logger = logging.getLogger("uvicorn.error")


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


def router(current_user, *, adapter=None, preference_service=None, search_service=None, verification_service=None, recommendation_service=None, image_service=None):
    api = APIRouter(tags=["AI recommendations"])
    adapter = adapter or RecordRecommendationAdapter()
    preference_service = preference_service or build_preference_service(LLM_PROVIDER)
    search_service = search_service or build_search_service(SEARCH_PROVIDER)
    verification_service = verification_service or KakaoPlaceVerificationService()
    recommendation_service = recommendation_service or build_recommendation_service(LLM_PROVIDER)
    image_service = image_service or RecommendationImageService()

    @api.get("/ai/recommendations", response_model=PlaceRecommendationResponse)
    def recommendations(
        exclude_place_ids: str | None = None,
        previous_place_ids: str | None = None,
        user=Depends(current_user),
        db: Session = Depends(require_db),
    ):
        records = adapter.list_positive_records(db, user.id)
        _log_diagnostic("positive_records_count", len(records))
        if not records:
            _log_diagnostic("extracted_keywords_count", 0)
            _log_diagnostic("tavily_candidates_count", 0)
            _log_diagnostic("ranking_output_count", 0)
            _log_diagnostic("validated_recommendations_count", 0)
            _log_diagnostic("final_response_count", 0)
            return PlaceRecommendationResponse()
        try:
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
                _log_diagnostic("ranking_output_count", 0)
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
        excluded_ids = {
            value.strip()
            for value in (exclude_place_ids or "").split(",")[:60]
            if value.strip()
        }
        previous_ids = {
            value.strip()
            for value in (previous_place_ids or "").split(",")[:3]
            if value.strip()
        }
        if excluded_ids:
            unseen = [
                item for item in candidates.candidates
                if item.kakao_place_id not in excluded_ids
            ]
            # Prefer unseen verified Kakao places whenever any remain. If the
            # pool is exhausted, reuse the validated pool instead of inventing
            # places or returning a misleading empty result.
            preferred = unseen
            if not preferred and previous_ids:
                preferred = [
                    item for item in candidates.candidates
                    if item.kakao_place_id not in previous_ids
                ]
            if preferred:
                candidates = candidates.model_copy(update={"candidates": preferred})
            _log_diagnostic("refresh_excluded_place_ids_count", len(excluded_ids))
            _log_diagnostic("refresh_unseen_verified_candidates_count", len(unseen))
            _log_diagnostic("refresh_previous_place_ids_count", len(previous_ids))
        try:
            if not candidates.candidates:
                _log_diagnostic("ranking_output_count", 0)
                _log_diagnostic("validated_recommendations_count", 0)
                _log_diagnostic("final_response_count", 0)
                return PlaceRecommendationResponse()
            result = recommendation_service.recommend(records, keywords.keywords, candidates)
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
