"""DTOs used only by the AI recommendation flow."""

from pydantic import BaseModel, Field


class PreferenceKeyword(BaseModel):
    keyword: str = Field(min_length=1, max_length=40)
    score: float = Field(ge=0, le=1)


class PreferenceKeywordResponse(BaseModel):
    keywords: list[PreferenceKeyword] = Field(default_factory=list, max_length=5)


class PlaceCandidate(BaseModel):
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
    rank: int = Field(ge=1, le=3)
    name: str = Field(min_length=1, max_length=160)
    address: str | None = None
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    match_score: float = Field(ge=0, le=1)
    matched_keywords: list[str] = Field(default_factory=list)
    reason: str = Field(min_length=1, max_length=500)
    source_url: str = Field(min_length=1)


class PlaceRecommendationResponse(BaseModel):
    recommendations: list[RecommendedPlace] = Field(default_factory=list, max_length=3)
