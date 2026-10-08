"""Personal saved places; all ownership comes from authenticated identity."""
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from sqlalchemy import case, delete, func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .record_models import Place, SavedPlace
from .records import require_db


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


def require_place(db: Session, place_id: int):
    if db.get(Place, place_id) is None:
        raise HTTPException(404, "장소를 찾을 수 없습니다.")


def saved_state(db: Session, user_id: int, place_id: int):
    total, matching = db.execute(select(
        func.count(), func.count(case((SavedPlace.place_id == place_id, 1))),
    ).where(SavedPlace.user_id == user_id)).one()
    return SavedPlaceState(place_id=place_id, saved=matching > 0, saved_count=total)


def router(current_user):
    api = APIRouter(tags=["Saved places"])

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
        if db.get(SavedPlace, (user.id, place_id)) is None:
            db.add(SavedPlace(user_id=user.id, place_id=place_id))
            try:
                db.commit()
            except IntegrityError:
                db.rollback()
                require_place(db, place_id)
                if db.get(SavedPlace, (user.id, place_id)) is None:
                    raise HTTPException(503, "장소를 저장하지 못했습니다.") from None
        return saved_state(db, user.id, place_id)

    @api.delete("/places/{place_id}/saved", response_model=SavedPlaceState)
    def unsave_place(place_id: int, user=Depends(current_user), db: Session = Depends(require_db)):
        require_place(db, place_id)
        db.execute(delete(SavedPlace).where(
            SavedPlace.user_id == user.id, SavedPlace.place_id == place_id))
        db.commit()
        return saved_state(db, user.id, place_id)

    return api
