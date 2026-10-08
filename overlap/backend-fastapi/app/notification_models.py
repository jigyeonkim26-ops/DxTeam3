"""Mappings for existing notification tables; no schema creation."""
from datetime import datetime, time

from sqlalchemy import Boolean, DateTime, ForeignKey, String, Text, Time, text
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base
from .record_models import Id


class Notification(Base):
    __tablename__ = "notifications"
    id: Mapped[int] = mapped_column(Id, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    type: Mapped[str] = mapped_column(String(50))
    title: Mapped[str] = mapped_column(String(255))
    message: Mapped[str] = mapped_column(Text)
    reference_type: Mapped[str | None] = mapped_column(String(50), nullable=True)
    reference_id: Mapped[int | None] = mapped_column(Id, nullable=True)
    is_read: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=text("CURRENT_TIMESTAMP"))


class NotificationSettings(Base):
    __tablename__ = "notification_settings"
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id"), primary_key=True)
    comments_replies_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    reactions_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    new_group_records_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    group_updates_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    nearby_reminder_enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    quiet_start_time: Mapped[time | None] = mapped_column(Time, nullable=True)
    quiet_end_time: Mapped[time | None] = mapped_column(Time, nullable=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=text("CURRENT_TIMESTAMP"))
