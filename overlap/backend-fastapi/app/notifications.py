from datetime import datetime, time, timezone

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, ConfigDict, field_validator
from sqlalchemy import func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .notification_models import Notification, NotificationSettings
from .records import require_db


class NotificationPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: int
    type: str
    title: str
    message: str
    reference_type: str | None
    reference_id: int | None
    is_read: bool
    created_at: datetime


class NotificationPage(BaseModel):
    items: list[NotificationPublic]
    total: int
    offset: int
    limit: int


class UnreadCount(BaseModel):
    unread_count: int


class SettingsPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    comments_replies_enabled: bool = True
    reactions_enabled: bool = True
    new_group_records_enabled: bool = True
    group_updates_enabled: bool = True
    nearby_reminder_enabled: bool = True
    quiet_start_time: time | None = None
    quiet_end_time: time | None = None
    updated_at: datetime | None = None


class SettingsInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    comments_replies_enabled: bool | None = None
    reactions_enabled: bool | None = None
    new_group_records_enabled: bool | None = None
    group_updates_enabled: bool | None = None
    nearby_reminder_enabled: bool | None = None
    quiet_start_time: time | None = None
    quiet_end_time: time | None = None

    @field_validator("comments_replies_enabled", "reactions_enabled", "new_group_records_enabled",
                     "group_updates_enabled", "nearby_reminder_enabled")
    @classmethod
    def nonnull_flag(cls, value):
        if value is None:
            raise ValueError("설정 값은 true 또는 false여야 합니다.")
        return value

    @field_validator("quiet_start_time", "quiet_end_time")
    @classmethod
    def local_time(cls, value):
        if value is not None and value.tzinfo is not None:
            raise ValueError("시간대 없는 HH:MM:SS 형식을 사용해 주세요.")
        return value


def unread_count(db: Session, user_id: int):
    return UnreadCount(unread_count=db.scalar(select(func.count()).select_from(Notification).where(
        Notification.user_id == user_id, Notification.is_read.is_(False))))


def router(current_user):
    api = APIRouter(tags=["Notifications"])

    @api.get("/notifications", response_model=NotificationPage)
    def list_notifications(user=Depends(current_user), db: Session = Depends(require_db),
                           offset: int = Query(default=0, ge=0),
                           limit: int = Query(default=20, ge=1, le=100)):
        query = select(Notification).where(Notification.user_id == user.id)
        total = db.scalar(select(func.count()).select_from(query.subquery()))
        rows = db.scalars(query.order_by(Notification.created_at.desc(), Notification.id.desc())
                          .offset(offset).limit(limit)).all()
        return NotificationPage(items=[NotificationPublic.model_validate(n) for n in rows],
                                total=total, offset=offset, limit=limit)

    @api.get("/notifications/unread-count", response_model=UnreadCount)
    def get_unread_count(user=Depends(current_user), db: Session = Depends(require_db)):
        return unread_count(db, user.id)

    @api.patch("/notifications/read-all", response_model=UnreadCount)
    def read_all(user=Depends(current_user), db: Session = Depends(require_db)):
        db.execute(update(Notification).where(Notification.user_id == user.id,
                                              Notification.is_read.is_(False)).values(is_read=True))
        db.commit()
        return unread_count(db, user.id)

    @api.get("/notifications/settings", response_model=SettingsPublic)
    def get_settings(user=Depends(current_user), db: Session = Depends(require_db)):
        settings = db.get(NotificationSettings, user.id)
        return SettingsPublic.model_validate(settings) if settings else SettingsPublic()

    @api.patch("/notifications/settings", response_model=SettingsPublic)
    def patch_settings(data: SettingsInput, user=Depends(current_user), db: Session = Depends(require_db)):
        settings = db.get(NotificationSettings, user.id)
        if settings is None:
            try:
                with db.begin_nested():
                    settings = NotificationSettings(user_id=user.id)
                    db.add(settings)
                    db.flush()
            except IntegrityError:
                settings = db.get(NotificationSettings, user.id)
                if settings is None:
                    raise HTTPException(503, "알림 설정을 저장하지 못했습니다.") from None
        for name, value in data.model_dump(exclude_unset=True).items():
            setattr(settings, name, value)
        settings.updated_at = datetime.now(timezone.utc).replace(tzinfo=None)
        db.commit()
        db.refresh(settings)
        return SettingsPublic.model_validate(settings)

    @api.patch("/notifications/{notification_id}/read", response_model=NotificationPublic)
    def read_one(notification_id: int, user=Depends(current_user), db: Session = Depends(require_db)):
        item = db.scalar(select(Notification).where(Notification.id == notification_id,
                                                     Notification.user_id == user.id))
        if item is None:
            raise HTTPException(404, "알림을 찾을 수 없습니다.")
        item.is_read = True
        db.commit()
        db.refresh(item)
        return NotificationPublic.model_validate(item)

    return api
