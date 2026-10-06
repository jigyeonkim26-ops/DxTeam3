"""API로 주고받을 데이터 형식. 날짜와 작성 시각을 따로 저장합니다."""

from datetime import date, datetime, timedelta, timezone
from typing import Annotated, Generic, Literal, TypeVar

from pydantic import BaseModel, ConfigDict, Field, SecretStr, StringConstraints, field_validator


def today_in_korea() -> date:
    return datetime.now(timezone(timedelta(hours=9))).date()


ShortName = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=60)]
Content = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=2000)]
Username = Annotated[str, StringConstraints(to_lower=True, pattern=r"^[a-zA-Z0-9_]{3,30}$")]


class InputModel(BaseModel):
    model_config = ConfigDict(extra="forbid")


class RegisterInput(InputModel):
    username: Username
    display_name: ShortName
    password: SecretStr = Field(min_length=8, max_length=128)


class LoginInput(InputModel):
    username: Username
    password: SecretStr = Field(min_length=1, max_length=128)


class UserPublic(BaseModel):
    id: int
    username: str
    display_name: str


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


class MemoryInput(InputModel):
    place_id: int = Field(gt=0)
    content: Content
    visited_on: date

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
    created_at: datetime
    updated_at: datetime


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
