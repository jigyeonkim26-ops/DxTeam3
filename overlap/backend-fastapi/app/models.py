"""API로 주고받을 데이터 형식. 날짜와 작성 시각을 따로 저장합니다."""

from datetime import date, datetime, timedelta, timezone
from typing import Annotated, Generic, Literal, TypeVar

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    SecretStr,
    StringConstraints,
    field_validator,
    model_validator,
)


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
        return validate_birth_date(value)

    @field_validator("terms_accepted")
    @classmethod
    def require_terms_acceptance(cls, value: bool) -> bool:
        if not value:
            raise ValueError("필수 약관에 동의해 주세요.")
        return value


def validate_birth_date(value: date) -> date:
    if value > today_in_korea():
        raise ValueError("생년월일은 미래 날짜일 수 없습니다.")
    return value


class ProfileUpdateInput(InputModel):
    nickname: Nickname | None = None
    birth_date: date | None = None
    gender: Literal["female", "male"] | None = None

    @field_validator("birth_date")
    @classmethod
    def validate_updated_birth_date(cls, value: date | None) -> date | None:
        return validate_birth_date(value) if value is not None else None

    @model_validator(mode="after")
    def require_changed_fields(self):
        if not self.model_fields_set:
            raise ValueError("수정할 프로필 정보를 하나 이상 보내 주세요.")
        if any(getattr(self, field) is None for field in self.model_fields_set):
            raise ValueError("프로필 정보는 비워 둘 수 없습니다.")
        return self


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
    description: str | None = Field(default=None, max_length=500)
    visibility: Literal["INVITED_ONLY", "LINK_REQUEST_ALLOWED"] = "INVITED_ONLY"


class JoinInput(InputModel):
    invite_code: str = Field(min_length=10, max_length=128)


class GroupPublic(BaseModel):
    id: int
    name: str
    display_name: str | None = None
    member_count: int
    description: str | None = None
    visibility: str = "INVITED_ONLY"
    notifications_enabled: bool = True
    pin_color_value: int | None = None


class GroupCreated(GroupPublic):
    invite_code: str


class GroupUpdateInput(InputModel):
    description: str | None = Field(default=None, max_length=500)
    visibility: Literal["INVITED_ONLY", "LINK_REQUEST_ALLOWED"]


class GroupPreferencesInput(InputModel):
    custom_name: str | None = Field(default=None, max_length=100)
    notifications_enabled: bool | None = None
    pin_color_value: int | None = Field(default=None, ge=0, le=4294967295)


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
