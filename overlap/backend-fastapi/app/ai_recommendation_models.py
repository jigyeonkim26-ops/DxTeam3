"""DTOs used only by the AI recommendation flow."""

from typing import Literal

from pydantic import BaseModel, Field


class PreferenceKeyword(BaseModel):
    keyword: str = Field(min_length=1, max_length=40)
    score: float = Field(ge=0, le=1)


class PreferenceKeywordResponse(BaseModel):
    keywords: list[PreferenceKeyword] = Field(default_factory=list, max_length=5)


class PlaceCandidate(BaseModel):
    kakao_place_id: str | None = None
    name: str = Field(min_length=1, max_length=160)
    address: str | None = None
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    matched_keywords: list[str] = Field(default_factory=list)
    summary: str = Field(min_length=1, max_length=500)
    source_url: str = Field(min_length=1)


class PlaceCandidateResponse(BaseModel):
    candidates: list[PlaceCandidate] = Field(default_factory=list, max_length=10)


class RecommendedPlace(BaseModel):
    kakao_place_id: str | None = None
    rank: int = Field(ge=1, le=10)
    name: str = Field(min_length=1, max_length=160)
    address: str | None = None
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    match_score: float = Field(ge=0, le=1)
    matched_keywords: list[str] = Field(default_factory=list)
    reason: str = Field(min_length=1, max_length=500)
    source_url: str = Field(min_length=1)
    image_url: str | None = None
    image_source: str | None = None
    image_origin_type: Literal["record", "external", "placeholder"] = "placeholder"
    image_credit: str | None = None


class PlaceRecommendationResponse(BaseModel):
    # The service ranks a bounded, verified pool; the API returns at most three per page.
    recommendations: list[RecommendedPlace] = Field(default_factory=list, max_length=10)
    session_status: Literal["available", "exhausted", "empty"] = "available"
