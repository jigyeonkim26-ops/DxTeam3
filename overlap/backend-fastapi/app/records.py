"""Personal records and feeds; all visibility checks happen on the server."""
import io
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, File, Form, HTTPException, Query, UploadFile
from fastapi.responses import StreamingResponse
from PIL import Image, UnidentifiedImageError
from pydantic import BaseModel, ConfigDict, Field, ValidationError, model_validator
from sqlalchemy import and_, exists, func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .db import get_db
from .db_models import User
from .object_storage import get_object_storage
from .record_models import GroupMember, MemoryGroup, Place, Record, RecordGroup, RecordPhoto


class RecordPlace(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    kakao_place_id: str = Field(min_length=1, max_length=100, pattern=r"^\d+$")
    name: str = Field(min_length=1, max_length=150)
    address: str = Field(max_length=255)
    latitude: float = Field(ge=-90, le=90, allow_inf_nan=False)
    longitude: float = Field(ge=-180, le=180, allow_inf_nan=False)


class RecordInput(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    place: RecordPlace
    emotion: Literal["excellent", "good", "okay", "neutral", "disappointed", "poor"]
    # Existing compose UI makes the story optional (maximum 300 characters).
    content: str = Field(default="", max_length=300)
    is_private: bool
    group_ids: list[Annotated[int, Field(gt=0)]] = Field(default_factory=list, max_length=100)

    @model_validator(mode="after")
    def validate_scope(self):
        if self.is_private and self.group_ids:
            raise ValueError("나만 보기 기록은 모임에 공유할 수 없습니다.")
        if not self.is_private and not self.group_ids:
            raise ValueError("공유할 모임을 선택해 주세요.")
        self.group_ids = list(dict.fromkeys(self.group_ids))
        return self


def require_db(db: Session | None = Depends(get_db)) -> Session:
    if db is None:
        raise HTTPException(503, "기록 기능은 MySQL 연결이 필요합니다.")
    return db


def visibility(user_id: int):
    shared = exists(select(RecordGroup.record_id).join(
        GroupMember, GroupMember.group_id == RecordGroup.group_id
    ).where(RecordGroup.record_id == Record.id, GroupMember.user_id == user_id))
    return or_(Record.author_id == user_id, and_(Record.is_private.is_(False), shared))


def groups_for_user(db: Session, user_id: int):
    counts = select(func.count()).select_from(GroupMember).where(
        GroupMember.group_id == MemoryGroup.id).correlate(MemoryGroup).scalar_subquery()
    return [dict(id=g.id, name=g.name, description=g.description or "", member_count=count)
            for g, count in db.execute(select(MemoryGroup, counts).join(
                GroupMember, GroupMember.group_id == MemoryGroup.id
            ).where(GroupMember.user_id == user_id).order_by(MemoryGroup.name))]


def record_public(db: Session, record: Record, viewer_id: int):
    author = db.get(User, record.author_id)
    place = db.get(Place, record.place_id)
    photos = db.scalars(select(RecordPhoto).where(RecordPhoto.record_id == record.id)
                        .order_by(RecordPhoto.sort_order, RecordPhoto.id)).all()
    # A shared record can also be shared to other groups; don't reveal their names.
    groups = db.scalars(select(MemoryGroup).join(RecordGroup).join(
        GroupMember, GroupMember.group_id == MemoryGroup.id
    ).where(RecordGroup.record_id == record.id, GroupMember.user_id == viewer_id)).all()
    return dict(
        id=record.id, author=dict(id=author.id, name=author.nickname or "사용자"),
        place=dict(id=place.id, name=place.name, address=place.address,
                   latitude=float(place.latitude), longitude=float(place.longitude)),
        content=record.content, emotion=record.emotion, is_private=record.is_private,
        created_at=record.created_at.isoformat() + "Z",
        photo_urls=[f"/records/{record.id}/photos/{p.id}" for p in photos],
        shared_groups=[dict(id=g.id, name=g.name) for g in groups],
    )


def router(current_user):
    api = APIRouter(tags=["Records"])

    @api.get("/records/groups")
    def my_groups(user=Depends(current_user), db: Session = Depends(require_db)):
        return groups_for_user(db, user.id)

    @api.post("/records", status_code=201)
    def create_record(
        data: Annotated[str, Form(max_length=50000)],
        photos: Annotated[list[UploadFile], File()],
        user=Depends(current_user), db: Session = Depends(require_db),
    ):
        try:
            payload = RecordInput.model_validate_json(data)
        except ValidationError:
            raise HTTPException(422, "장소·감정·내용·공개 범위를 확인해 주세요.") from None
        if not 1 <= len(photos) <= 5:
            raise HTTPException(422, "사진은 1~5장 선택해 주세요.")
        members = set(db.scalars(select(GroupMember.group_id).where(
            GroupMember.user_id == user.id, GroupMember.group_id.in_(payload.group_ids))))
        if members != set(payload.group_ids):
            raise HTTPException(403, "가입한 모임에만 공유할 수 있습니다.")
        images = []
        for photo in photos:
            raw = photo.file.read(10 * 1024 * 1024 + 1)
            if len(raw) > 10 * 1024 * 1024:
                raise HTTPException(413, "사진 한 장은 10MB 이하로 선택해 주세요.")
            try:
                with Image.open(io.BytesIO(raw)) as image:
                    mime = {"JPEG": "image/jpeg", "PNG": "image/png", "WEBP": "image/webp"}.get(image.format)
                    image.verify()
                if mime is None:
                    raise ValueError()
            except (ValueError, OSError, UnidentifiedImageError, Image.DecompressionBombError):
                raise HTTPException(422, "JPEG·PNG·WebP 사진 파일을 선택해 주세요.") from None
            images.append((raw, mime, (photo.filename or "photo").replace("\\", "/").split("/")[-1][:255]))
        # Dependency is called only after payload/membership/photo validation.
        storage = get_object_storage()
        uploaded = []
        try:
            place = db.scalar(select(Place).where(
                Place.provider == "kakao", Place.external_place_id == payload.place.kakao_place_id))
            if place is None:
                place = Place(provider="kakao", external_place_id=payload.place.kakao_place_id,
                              **payload.place.model_dump(exclude={"kakao_place_id"}))
                # A concurrent record may insert the same Kakao place first.
                try:
                    with db.begin_nested():
                        db.add(place)
                        db.flush()
                except IntegrityError:
                    place = db.scalar(select(Place).where(
                        Place.provider == "kakao", Place.external_place_id == payload.place.kakao_place_id))
                    if place is None:
                        raise
            record = Record(author_id=user.id, place_id=place.id, content=payload.content,
                            emotion=payload.emotion, is_private=payload.is_private)
            db.add(record)
            db.flush()
            for order, (raw, mime, name) in enumerate(images):
                photo = storage.upload(raw, mime)
                uploaded.append(photo)
                db.add(RecordPhoto(record_id=record.id, object_key=photo.object_key,
                                  photo_url=photo.photo_url, original_name=name, mime_type=mime,
                                  file_size=len(raw), sort_order=order))
            for group_id in payload.group_ids:
                db.add(RecordGroup(record_id=record.id, group_id=group_id))
            db.flush()
            response = record_public(db, record, user.id)
            db.commit()
            return response
        except Exception as error:
            db.rollback()
            for photo in uploaded:
                try:
                    storage.delete(photo.object_key)
                except Exception:
                    pass  # Never expose credentials or storage exception details.
            if isinstance(error, HTTPException):
                raise
            raise HTTPException(503, "기록을 저장하지 못했습니다. 다시 시도해 주세요.") from None

    @api.get("/feed")
    def feed(user=Depends(current_user), db: Session = Depends(require_db),
             mine: bool = False, group_id: int | None = Query(default=None, gt=0),
             offset: int = Query(default=0, ge=0), limit: int = Query(default=20, ge=1, le=100)):
        # Identity comes only from the authenticated dependency, never query input.
        # EXISTS limits shared records to joined groups; DISTINCT also protects
        # totals/pagination if the query later gains joins to multiple groups.
        query = select(Record).where(visibility(user.id)).distinct()
        if mine:
            query = query.where(Record.author_id == user.id)
        if group_id is not None:
            if db.get(GroupMember, (group_id, user.id)) is None:
                raise HTTPException(403, "가입한 모임만 조회할 수 있습니다.")
            query = query.where(exists(select(RecordGroup.record_id).where(
                RecordGroup.record_id == Record.id, RecordGroup.group_id == group_id)))
        total = db.scalar(select(func.count()).select_from(query.subquery()))
        records = db.scalars(query.order_by(Record.created_at.desc(), Record.id.desc())
                             .offset(offset).limit(limit)).all()
        return dict(items=[record_public(db, r, user.id) for r in records], total=total, offset=offset, limit=limit)

    @api.get("/records/{record_id}/photos/{photo_id}")
    def photo(record_id: int, photo_id: int, user=Depends(current_user), db: Session = Depends(require_db)):
        record = db.scalar(select(Record).where(Record.id == record_id, visibility(user.id)))
        photo = db.get(RecordPhoto, photo_id)
        if record is None or photo is None or photo.record_id != record_id:
            raise HTTPException(404, "사진을 찾을 수 없습니다.")
        body = get_object_storage().download(photo.object_key)
        def chunks():
            try:
                while chunk := body.read(64 * 1024):
                    yield chunk
            finally:
                body.close()
        return StreamingResponse(chunks(), media_type=photo.mime_type or "image/jpeg",
                                 headers={"Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff"})

    return api
