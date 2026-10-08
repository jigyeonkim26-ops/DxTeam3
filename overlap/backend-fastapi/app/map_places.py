"""Map pins aggregated from records visible to the authenticated user."""
from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from .record_models import Place, Record, RecordGroup, GroupMember
from .records import require_db, visibility


class MapPlace(BaseModel):
    place_id: int
    name: str
    address: str | None
    latitude: float
    longitude: float
    record_count: int
    has_mine: bool
    group_ids: list[int]


def router(current_user):
    api = APIRouter(tags=["Map"])

    @api.get("/map/places", response_model=list[MapPlace])
    def map_places(user=Depends(current_user), db: Session = Depends(require_db)):
        # EXISTS in visibility avoids multiplying records shared to several groups.
        # Only internal place PKs join records; external Kakao IDs are not user IDs
        # or record foreign keys. Identity comes exclusively from current_user.
        counts = select(
            Record.place_id, func.count(Record.id).label("record_count")
        ).where(visibility(user.id)).group_by(Record.place_id).subquery()
        query = select(
            Place.id.label("place_id"), Place.name, Place.address,
            Place.latitude, Place.longitude, counts.c.record_count,
        ).join(counts, counts.c.place_id == Place.id).order_by(Place.id)
        rows = [dict(row) for row in db.execute(query).mappings().all()]
        mine = set(db.scalars(select(Record.place_id).where(
            visibility(user.id), Record.author_id == user.id)))
        memberships = db.execute(select(Record.place_id, RecordGroup.group_id)
            .join(RecordGroup, RecordGroup.record_id == Record.id)
            .join(GroupMember, GroupMember.group_id == RecordGroup.group_id)
            .where(visibility(user.id), Record.is_private.is_(False),
                   GroupMember.user_id == user.id).distinct()).all()
        groups = {}
        for place_id, group_id in memberships:
            groups.setdefault(place_id, set()).add(group_id)
        for row in rows:
            row['has_mine'] = row['place_id'] in mine
            row['group_ids'] = sorted(groups.get(row['place_id'], set()))
        return rows

    return api
