"""Read-only conversion of a user's Record rows into recommendation input data."""

from datetime import date, datetime
from enum import Enum

from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.orm import Session

from .record_models import Place, Record


class RecommendationEmotionCode(str, Enum):
    LOVE = "LOVE"
    LIKE = "LIKE"
    GOOD = "GOOD"
    NEUTRAL = "NEUTRAL"
    DISAPPOINTED = "DISAPPOINTED"
    BAD = "BAD"


class RecommendationRecord(BaseModel):
    record_id: int
    user_id: int
    place_id: int
    place_name: str | None = None
    address: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    content: str
    emotion_code: RecommendationEmotionCode
    emotion_meaning: str
    # Records currently have no visit-date column. Never derive one from created_at.
    visited_on: date | None = None
    created_at: datetime | None = None


class RecordRecommendationAdapter:
    """Select only the authenticated user's positive database records."""

    EMOTION_MAPPING = {
        "excellent": (RecommendationEmotionCode.LOVE, "최고"),
        "good": (RecommendationEmotionCode.LIKE, "좋아"),
        "okay": (RecommendationEmotionCode.GOOD, "괜찮아"),
        "neutral": (RecommendationEmotionCode.NEUTRAL, "그저 그래"),
        "disappointed": (RecommendationEmotionCode.DISAPPOINTED, "아쉬워"),
        "poor": (RecommendationEmotionCode.BAD, "별로"),
    }
    POSITIVE_EMOTIONS = frozenset({"excellent", "good", "okay"})

    @classmethod
    def to_recommendation_record(cls, record: Record, place: Place | None) -> RecommendationRecord:
        code, meaning = cls.EMOTION_MAPPING[record.emotion]
        return RecommendationRecord(
            record_id=record.id,
            user_id=record.author_id,
            place_id=record.place_id,
            place_name=place.name if place is not None else None,
            address=(place.road_address or place.address) if place is not None else None,
            latitude=float(place.latitude) if place is not None and place.latitude is not None else None,
            longitude=float(place.longitude) if place is not None and place.longitude is not None else None,
            content=record.content,
            emotion_code=code,
            emotion_meaning=meaning,
            visited_on=None,
            created_at=record.created_at,
        )

    def list_positive_records(self, db: Session, user_id: int) -> list[RecommendationRecord]:
        statement = (
            select(Record, Place)
            .outerjoin(Place, Record.place_id == Place.id)
            .where(Record.author_id == user_id, Record.emotion.in_(self.POSITIVE_EMOTIONS))
            .order_by(Record.created_at.desc(), Record.id.desc())
        )
        return [self.to_recommendation_record(record, place) for record, place in db.execute(statement)]
