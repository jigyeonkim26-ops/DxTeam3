"""Authenticated AI recommendation endpoint over existing database records."""

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from .ai_recommendation_errors import AIConfigurationError, AIRecommendationError
from .ai_recommendation_models import PlaceRecommendationResponse
from .config import LLM_PROVIDER, SEARCH_PROVIDER
from .records import require_db
from .recommendation_record_adapter import RecordRecommendationAdapter
from .provider_factory import build_preference_service, build_recommendation_service, build_search_service


def router(current_user, *, adapter=None, preference_service=None, search_service=None, recommendation_service=None):
    api = APIRouter(tags=["AI recommendations"])
    adapter = adapter or RecordRecommendationAdapter()
    preference_service = preference_service or build_preference_service(LLM_PROVIDER)
    search_service = search_service or build_search_service(SEARCH_PROVIDER)
    recommendation_service = recommendation_service or build_recommendation_service(LLM_PROVIDER)

    @api.get("/ai/recommendations", response_model=PlaceRecommendationResponse)
    def recommendations(user=Depends(current_user), db: Session = Depends(require_db)):
        records = adapter.list_positive_records(db, user.id)
        if not records:
            return PlaceRecommendationResponse()
        try:
            keywords = preference_service.extract_keywords(records)
            if not keywords.keywords:
                return PlaceRecommendationResponse()
            candidates = search_service.search_candidates(keywords.keywords, records)
            if not candidates.candidates:
                return PlaceRecommendationResponse()
            return recommendation_service.recommend(records, keywords.keywords, candidates)
        except AIConfigurationError as exc:
            raise HTTPException(503, "AI recommendation provider is not configured") from exc
        except AIRecommendationError as exc:
            raise HTTPException(502, "AI recommendation provider request failed") from exc

    return api
