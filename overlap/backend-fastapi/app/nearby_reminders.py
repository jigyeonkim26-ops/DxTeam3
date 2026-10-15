"""On-demand nearby reminders for the authenticated user's own records.

The client supplies a location only for this request.  It is never persisted.
"""
import math
from datetime import datetime, timedelta, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select
from sqlalchemy.orm import Session

from .notification_models import Notification, NotificationSettings
from .record_models import Place, Record
from .records import record_public, require_db


_RADIUS_METERS = 500.0
_DUPLICATE_WINDOW = timedelta(hours=24)
_REMINDER_TYPE = "NEARBY_REMINDER"


class NearbyReminderRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    latitude: float = Field(ge=-90, le=90, allow_inf_nan=False)
    longitude: float = Field(ge=-180, le=180, allow_inf_nan=False)


class NearbyReminderItem(BaseModel):
    record: dict[str, Any]
    distance_meters: int
    notification_id: int
    notification_created: bool


class NearbyReminderResponse(BaseModel):
    items: list[NearbyReminderItem]


def _distance_meters(
    latitude_a: float,
    longitude_a: float,
    latitude_b: float,
    longitude_b: float,
) -> float:
    """Great-circle distance.  Kept in Python so the API works in SQLite tests.

    Candidate records are owned by one user, so this on-demand query stays
    small and does not require database-specific spatial SQL or schema changes.
    """
    lat_a, lon_a, lat_b, lon_b = map(
        math.radians, (latitude_a, longitude_a, latitude_b, longitude_b)
    )
    latitude_delta = lat_b - lat_a
    longitude_delta = lon_b - lon_a
    haversine = (
        math.sin(latitude_delta / 2) ** 2
        + math.cos(lat_a) * math.cos(lat_b) * math.sin(longitude_delta / 2) ** 2
    )
    return 6_371_000 * 2 * math.asin(math.sqrt(min(1.0, haversine)))


def _reminder_allowed(db: Session, user_id: int) -> bool:
    settings = db.get(NotificationSettings, user_id)
    return settings is None or settings.nearby_reminder_enabled


def router(current_user):
    api = APIRouter(tags=["Nearby reminders"])

    @api.post("/reminders/nearby", response_model=NearbyReminderResponse)
    def nearby_reminders(
        payload: NearbyReminderRequest,
        user=Depends(current_user),
        db: Session = Depends(require_db),
    ):
        if not _reminder_allowed(db, user.id):
            return NearbyReminderResponse(items=[])

        # The author filter deliberately includes both private and shared
        # records: this feature is for the current user's own memories only.
        rows = db.execute(
            select(Record, Place)
            .join(Place, Place.id == Record.place_id)
            .where(
                Record.author_id == user.id,
                Place.latitude.is_not(None),
                Place.longitude.is_not(None),
            )
        ).all()
        matches = []
        for record, place in rows:
            distance = _distance_meters(
                payload.latitude,
                payload.longitude,
                float(place.latitude),
                float(place.longitude),
            )
            if distance <= _RADIUS_METERS:
                matches.append((distance, record))
        matches.sort(key=lambda item: (item[0], -item[1].id))

        now = datetime.now(timezone.utc).replace(tzinfo=None)
        cutoff = now - _DUPLICATE_WINDOW
        items: list[NearbyReminderItem] = []
        try:
            for distance, record in matches:
                recent_notification = db.scalar(
                    select(Notification)
                    .where(
                        Notification.user_id == user.id,
                        Notification.type == _REMINDER_TYPE,
                        Notification.reference_type == "RECORD",
                        Notification.reference_id == record.id,
                        Notification.created_at >= cutoff,
                    )
                    .order_by(Notification.created_at.desc(), Notification.id.desc())
                    .limit(1)
                )
                created = recent_notification is None
                if recent_notification is None:
                    place = db.get(Place, record.place_id)
                    recent_notification = Notification(
                        user_id=user.id,
                        type=_REMINDER_TYPE,
                        title="근처에 기록한 장소가 있어요",
                        message=f"{place.name}에서 남긴 기록을 다시 살펴보세요.",
                        reference_type="RECORD",
                        reference_id=record.id,
                        is_read=False,
                    )
                    db.add(recent_notification)
                    db.flush()
                items.append(
                    NearbyReminderItem(
                        record=record_public(db, record, user.id),
                        distance_meters=round(distance),
                        notification_id=recent_notification.id,
                        notification_created=created,
                    )
                )
            if matches:
                db.commit()
        except Exception as error:
            db.rollback()
            raise HTTPException(
                503, "근처 기록을 확인하지 못했습니다. 다시 시도해 주세요."
            ) from error
        return NearbyReminderResponse(items=items)

    return api
