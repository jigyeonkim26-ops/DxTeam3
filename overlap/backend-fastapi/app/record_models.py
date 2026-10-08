"""Mappings for the existing MySQL record tables; no automatic schema creation."""
from datetime import datetime

from sqlalchemy import BigInteger, Integer, Boolean, DateTime, Numeric, String, Text, ForeignKey, text
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base
from .group_db_models import GroupMember, MemoryGroup  # Re-export the shared group models.

Id = BigInteger().with_variant(Integer, "sqlite")


class Place(Base):
    __tablename__ = "places"
    id: Mapped[int] = mapped_column(Id, primary_key=True, autoincrement=True)
    provider: Mapped[str | None] = mapped_column(String(20))
    external_place_id: Mapped[str | None] = mapped_column(String(100))
    name: Mapped[str] = mapped_column(String(150))
    address: Mapped[str | None] = mapped_column(String(255))
    road_address: Mapped[str | None] = mapped_column(String(255))
    latitude: Mapped[float] = mapped_column(Numeric(10, 7))
    longitude: Mapped[float] = mapped_column(Numeric(10, 7))
    place_url: Mapped[str | None] = mapped_column(String(500))
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=text("CURRENT_TIMESTAMP"))


class Record(Base):
    __tablename__ = "records"
    id: Mapped[int] = mapped_column(Id, primary_key=True, autoincrement=True)
    author_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    place_id: Mapped[int] = mapped_column(ForeignKey("places.id"))
    content: Mapped[str] = mapped_column(Text)
    emotion: Mapped[str] = mapped_column(String(30))
    is_private: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=text("CURRENT_TIMESTAMP"))
    updated_at: Mapped[datetime] = mapped_column(DateTime, server_default=text("CURRENT_TIMESTAMP"))


class RecordPhoto(Base):
    __tablename__ = "record_photos"
    id: Mapped[int] = mapped_column(Id, primary_key=True, autoincrement=True)
    record_id: Mapped[int] = mapped_column(ForeignKey("records.id"))
    object_key: Mapped[str] = mapped_column(String(500))
    # Additive migration keeps existing object keys and rows intact.
    photo_url: Mapped[str | None] = mapped_column(String(500))
    original_name: Mapped[str | None] = mapped_column(String(255))
    mime_type: Mapped[str | None] = mapped_column(String(100))
    file_size: Mapped[int | None] = mapped_column(BigInteger)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, server_default=text("CURRENT_TIMESTAMP"))


class RecordGroup(Base):
    __tablename__ = "record_groups"
    record_id: Mapped[int] = mapped_column(ForeignKey("records.id"), primary_key=True)
    group_id: Mapped[int] = mapped_column(ForeignKey("memory_groups.id"), primary_key=True)
    shared_at: Mapped[datetime] = mapped_column(DateTime, server_default=text("CURRENT_TIMESTAMP"))
