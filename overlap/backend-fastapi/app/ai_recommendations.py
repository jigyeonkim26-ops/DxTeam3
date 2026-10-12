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
from .provider_factory import build_preference_service, build_recommendation_service, build_search_service

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


def router(current_user, *, adapter=None, preference_service=None, search_service=None, recommendation_service=None):
    api = APIRouter(tags=["AI recommendations"])
    adapter = adapter or RecordRecommendationAdapter()
    preference_service = preference_service or build_preference_service(LLM_PROVIDER)
    search_service = search_service or build_search_service(SEARCH_PROVIDER)
    recommendation_service = recommendation_service or build_recommendation_service(LLM_PROVIDER)

    @api.get("/ai/recommendations", response_model=PlaceRecommendationResponse)
    def recommendations(user=Depends(current_user), db: Session = Depends(require_db)):
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
            if not candidates.candidates:
                _log_diagnostic("ranking_output_count", 0)
                _log_diagnostic("validated_recommendations_count", 0)
                _log_diagnostic("final_response_count", 0)
                return PlaceRecommendationResponse()
            return recommendation_service.recommend(records, keywords.keywords, candidates)
        except AIConfigurationError as exc:
            raise HTTPException(503, "AI recommendation provider is not configured") from exc
        except AIRecommendationError as exc:
            _log_provider_failure("openrouter_top3_ranking", exc)
            raise HTTPException(502, "AI recommendation provider request failed") from exc
    return api
