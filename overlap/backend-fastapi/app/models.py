"""API로 주고받을 데이터 형식. 날짜와 작성 시각을 따로 저장합니다."""

from datetime import date, datetime, timedelta, timezone
from enum import Enum
from typing import Annotated, Generic, Literal, TypeVar

from pydantic import BaseModel, ConfigDict, Field, SecretStr, StringConstraints, field_validator


def today_in_korea() -> date:
    return datetime.now(timezone(timedelta(hours=9))).date()


ShortName = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=60)]
Content = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=2000)]
Email = Annotated[
    str,
    StringConstraints(
        strip_whitespace=True,
        to_lower=True,
        min_length=3,
        max_length=254,
        pattern=r"^[^@\s]+@[^@\s]+\.[^@\s]+$",
    ),
]
Nickname = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=50)]


class InputModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class RegisterInput(InputModel):
    email: Email
    password: SecretStr = Field(min_length=8, max_length=128)
    nickname: Nickname
    birth_date: date
    gender: Literal["female", "male"]
    terms_accepted: bool

    @field_validator("birth_date")
    @classmethod
    def validate_birth_date(cls, value: date) -> date:
        if value > today_in_korea():
            raise ValueError("생년월일은 미래 날짜일 수 없습니다.")
        return value

    @field_validator("terms_accepted")
    @classmethod
    def require_terms_acceptance(cls, value: bool) -> bool:
        if not value:
            raise ValueError("필수 약관에 동의해 주세요.")
        return value


class LoginInput(InputModel):
    email: Email
    password: SecretStr = Field(min_length=1, max_length=128)


class UserPublic(BaseModel):
    id: int
    email: str
    nickname: str
    birth_date: date
    gender: Literal["female", "male"]


class TokenOutput(BaseModel):
    access_token: str
    token_type: Literal["bearer"] = "bearer"
    expires_in: int


class GroupInput(InputModel):
    name: ShortName


class JoinInput(InputModel):
    invite_code: str = Field(min_length=10, max_length=128)


class GroupPublic(BaseModel):
    id: int
    name: str
    owner_id: int
    member_count: int


class GroupCreated(GroupPublic):
    invite_code: str


class InviteOutput(BaseModel):
    invite_code: str


class PlaceInput(InputModel):
    name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=120)]
    address: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=300)]
    latitude: float = Field(ge=-90, le=90, allow_inf_nan=False)
    longitude: float = Field(ge=-180, le=180, allow_inf_nan=False)


class PlacePublic(PlaceInput):
    id: int
    group_id: int


class EmotionCode(str, Enum):
    LOVE = "LOVE"
    LIKE = "LIKE"
    GOOD = "GOOD"
    NEUTRAL = "NEUTRAL"
    DISAPPOINTED = "DISAPPOINTED"
    BAD = "BAD"


def emotion_code_to_text(emotion_code: EmotionCode) -> str:
    return {
        EmotionCode.LOVE: "\ucd5c\uace0",
        EmotionCode.LIKE: "\uc88b\uc544",
        EmotionCode.GOOD: "\uad1c\ucc2e\uc544",
        EmotionCode.NEUTRAL: "\uadf8\uc800 \uadf8\ub798",
        EmotionCode.DISAPPOINTED: "\uc544\uc26c\uc6cc",
        EmotionCode.BAD: "\ubcc4\ub85c",
    }[emotion_code]


class MemoryInput(InputModel):
    place_id: int = Field(gt=0)
    content: Content
    visited_on: date
    emotion_code: EmotionCode = EmotionCode.NEUTRAL

    @field_validator("visited_on")
    @classmethod
    def validate_visit_date(cls, value: date) -> date:
        if value > today_in_korea():
            raise ValueError("추억 날짜는 한국 시간 기준 오늘 또는 이전 날짜여야 합니다.")
        return value


class MemoryPublic(BaseModel):
    id: int
    group_id: int
    place_id: int
    author: UserPublic
    content: str
    visited_on: date
    emotion_code: EmotionCode = EmotionCode.NEUTRAL
    created_at: datetime
    updated_at: datetime


class RecommendationMemory(BaseModel):
    memory_id: int
    user_id: int
    place_id: int
    place_name: str
    address: str
    latitude: float
    longitude: float
    content: str
    emotion_code: EmotionCode
    emotion_meaning: str
    visited_on: date
    created_at: datetime


class PreferenceKeyword(BaseModel):
    keyword: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=40)]
    score: float = Field(ge=0, le=1, allow_inf_nan=False)


class PreferenceKeywordResponse(BaseModel):
    keywords: list[PreferenceKeyword] = Field(max_length=5)


class PlaceCandidate(BaseModel):
    name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=160)]
    address: str | None = None
    latitude: float | None = Field(default=None, ge=-90, le=90, allow_inf_nan=False)
    longitude: float | None = Field(default=None, ge=-180, le=180, allow_inf_nan=False)
    matched_keywords: list[str]
    summary: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=500)]
    source_url: str


class PlaceCandidateResponse(BaseModel):
    candidates: list[PlaceCandidate] = Field(max_length=10)


class RecommendedPlace(BaseModel):
    rank: int = Field(ge=1, le=3)
    name: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=160)]
    address: str | None = None
    latitude: float | None = Field(default=None, ge=-90, le=90, allow_inf_nan=False)
    longitude: float | None = Field(default=None, ge=-180, le=180, allow_inf_nan=False)
    match_score: float = Field(ge=0, le=1, allow_inf_nan=False)
    matched_keywords: list[str]
    reason: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=500)]
    source_url: str


class PlaceRecommendationResponse(BaseModel):
    recommendations: list[RecommendedPlace] = Field(max_length=3)


class MapPin(BaseModel):
    place: PlacePublic
    memory_count: int
    contributor_count: int
    first_visited_on: date
    last_visited_on: date


T = TypeVar("T")


class Page(BaseModel, Generic[T]):
    items: list[T]
    total: int
    offset: int
    limit: int
