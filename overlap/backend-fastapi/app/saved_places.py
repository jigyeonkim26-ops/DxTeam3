"""Personal saved places; all ownership comes from authenticated identity."""
from datetime import datetime
import math

from fastapi import APIRouter, Depends, HTTPException, Path, Query
from pydantic import BaseModel, Field
import httpx
from sqlalchemy import case, delete, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .kakao import search_places
from .record_models import Place, Record, SavedPlace
from .records import require_db, visibility


class SavedPlaceState(BaseModel):
    place_id: int
    saved: bool
    saved_count: int


class SavedPlacePublic(BaseModel):
    place_id: int
    name: str
    address: str | None
    road_address: str | None
    latitude: float
    longitude: float
    created_at: datetime


class SavedPlacePage(BaseModel):
    items: list[SavedPlacePublic]
    total: int
    offset: int
    limit: int


class KakaoPlaceLookup(BaseModel):
    place_id: int | None
    saved: bool
    record_count: int


class KakaoPlaceSaveInput(BaseModel):
    name: str = Field(min_length=1, max_length=150)
    address: str = Field(min_length=1, max_length=255)


def require_place(db: Session, place_id: int):
    if db.get(Place, place_id) is None:
        raise HTTPException(404, "장소를 찾을 수 없습니다.")


def saved_state(db: Session, user_id: int, place_id: int):
    total, matching = db.execute(select(
        func.count(), func.count(case((SavedPlace.place_id == place_id, 1))),
    ).where(SavedPlace.user_id == user_id)).one()
    return SavedPlaceState(place_id=place_id, saved=matching > 0, saved_count=total)


def kakao_place(db: Session, kakao_place_id: str) -> Place | None:
    return db.scalar(select(Place).where(
        Place.provider == "kakao", Place.external_place_id == kakao_place_id,
    ))


def save_existing_place(db: Session, user_id: int, place_id: int) -> SavedPlaceState:
    if db.get(SavedPlace, (user_id, place_id)) is None:
        db.add(SavedPlace(user_id=user_id, place_id=place_id))
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            require_place(db, place_id)
            if db.get(SavedPlace, (user_id, place_id)) is None:
                raise HTTPException(503, "장소를 저장하지 못했습니다.") from None
    return saved_state(db, user_id, place_id)


def router(current_user):
    api = APIRouter(tags=["Saved places"])

    @api.get("/places/kakao/{kakao_place_id}", response_model=KakaoPlaceLookup)
    def lookup_kakao_place(
        kakao_place_id: str = Path(pattern=r"^\d+$"),
        user=Depends(current_user), db: Session = Depends(require_db),
    ):
        place = kakao_place(db, kakao_place_id)
        if place is None:
            return KakaoPlaceLookup(place_id=None, saved=False, record_count=0)
        count = db.scalar(select(func.count(Record.id)).where(
            Record.place_id == place.id, visibility(user.id),
        )) or 0
        return KakaoPlaceLookup(
            place_id=place.id,
            saved=db.get(SavedPlace, (user.id, place.id)) is not None,
            record_count=count,
        )

    @api.post("/places/kakao/{kakao_place_id}/saved", response_model=SavedPlaceState)
    def save_kakao_place(
        payload: KakaoPlaceSaveInput,
        kakao_place_id: str = Path(pattern=r"^\d+$"),
        user=Depends(current_user), db: Session = Depends(require_db),
    ):
        place = kakao_place(db, kakao_place_id)
        if place is None:
            region = payload.address.split()[0]
            try:
                matches = search_places(f"{region} {payload.name}", timeout=6.0)
            except RuntimeError as exc:
                raise HTTPException(503, "카카오 장소 검색이 설정되지 않았습니다.") from exc
            except (httpx.HTTPError, KeyError, TypeError, ValueError) as exc:
                raise HTTPException(502, "카카오 장소를 확인하지 못했습니다.") from exc
            verified = next((item for item in matches if (
                isinstance(item, dict)
                and item.get("kakao_place_id") == kakao_place_id
                and isinstance(item.get("name"), str)
                and item["name"].strip() == payload.name.strip()
                and isinstance(item.get("address"), str)
                and item["address"].split()
                and item["address"].split()[0] == region
            )), None)
            if verified is None:
                raise HTTPException(422, "카카오에서 확인된 장소와 일치하지 않습니다.")
            try:
                latitude, longitude = float(verified["latitude"]), float(verified["longitude"])
                if (not math.isfinite(latitude) or not math.isfinite(longitude)
                        or not -90 <= latitude <= 90 or not -180 <= longitude <= 180):
                    raise ValueError()
            except (KeyError, TypeError, ValueError) as exc:
                raise HTTPException(502, "카카오 장소 좌표가 올바르지 않습니다.") from exc
            place = Place(
                provider="kakao", external_place_id=kakao_place_id,
                name=verified["name"], address=verified["address"],
                latitude=latitude, longitude=longitude,
                place_url=verified.get("place_url"),
            )
            try:
                with db.begin_nested():
                    db.add(place)
                    db.flush()
            except IntegrityError:
                place = kakao_place(db, kakao_place_id)
                if place is None:
                    raise HTTPException(503, "장소를 저장하지 못했습니다.") from None
        return save_existing_place(db, user.id, place.id)

    @api.get("/places/saved", response_model=SavedPlacePage)
    def list_saved_places(
        user=Depends(current_user), db: Session = Depends(require_db),
        offset: int = Query(default=0, ge=0), limit: int = Query(default=20, ge=1, le=100),
    ):
        query = select(Place, SavedPlace.created_at).join(
            SavedPlace, SavedPlace.place_id == Place.id).where(SavedPlace.user_id == user.id)
        total = db.scalar(select(func.count()).select_from(query.subquery()))
        rows = db.execute(query.order_by(SavedPlace.created_at.desc(), Place.id.desc())
                          .offset(offset).limit(limit)).all()
        return SavedPlacePage(items=[SavedPlacePublic(
            place_id=p.id, name=p.name, address=p.address, road_address=p.road_address,
            latitude=float(p.latitude), longitude=float(p.longitude), created_at=created,
        ) for p, created in rows], total=total, offset=offset, limit=limit)

    @api.get("/places/{place_id}/saved", response_model=SavedPlaceState)
    def get_saved_state(place_id: int, user=Depends(current_user), db: Session = Depends(require_db)):
        require_place(db, place_id)
        return saved_state(db, user.id, place_id)

    @api.post("/places/{place_id}/saved", response_model=SavedPlaceState)
    def save_place(place_id: int, user=Depends(current_user), db: Session = Depends(require_db)):
        require_place(db, place_id)
        return save_existing_place(db, user.id, place_id)

    @api.delete("/places/{place_id}/saved", response_model=SavedPlaceState)
    def unsave_place(place_id: int, user=Depends(current_user), db: Session = Depends(require_db)):
        require_place(db, place_id)
        db.execute(delete(SavedPlace).where(
            SavedPlace.user_id == user.id, SavedPlace.place_id == place_id))
        db.commit()
        return saved_state(db, user.id, place_id)

    return api
