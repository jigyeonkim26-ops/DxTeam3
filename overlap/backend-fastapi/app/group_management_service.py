from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from .group_db_models import GroupMember, MemoryGroup
from .models import GroupCreated, GroupPreferencesInput, GroupPublic, GroupUpdateInput
from . import group_repository
from .notification_service import notify_group_members


def _member(db: Session, group_id: int, user_id: int) -> GroupMember:
    member = db.get(GroupMember, {"group_id": group_id, "user_id": user_id})
    if member is None:
        raise HTTPException(status_code=404, detail="모임을 찾을 수 없습니다.")
    return member


def _public(db: Session, group: MemoryGroup, user_id: int) -> GroupPublic:
    member = _member(db, group.id, user_id)
    return GroupPublic(
        id=group.id, name=group.name,
        display_name=member.custom_name or group.name,
        member_count=group_repository.count_members(db, group.id),
        description=group.description, visibility=group.visibility,
        notifications_enabled=member.notifications_enabled, pin_color_value=member.pin_color_value,
    )


def create_group(db: Session, *, user_id: int, name: str, description: str | None, visibility: str) -> GroupCreated:
    from .group_service import create_group as create_with_invite

    created = create_with_invite(db, user_id=user_id, name=name, description=description, visibility=visibility)
    group = group_repository.get_group(db, created.id)
    return GroupCreated(**_public(db, group, user_id).model_dump(), invite_code=created.invite_code)


def update_group(db: Session, *, user_id: int, group_id: int, data: GroupUpdateInput) -> GroupPublic:
    _member(db, group_id, user_id)
    group = db.scalar(select(MemoryGroup).where(MemoryGroup.id == group_id).with_for_update())
    if group is None:
        raise HTTPException(status_code=404, detail="모임을 찾을 수 없습니다.")
    changed = (group.description, group.visibility) != (data.description, data.visibility)
    try:
        group.description, group.visibility = data.description, data.visibility
        if changed:
            notify_group_members(db, group_ids=[group_id], actor_id=user_id)
        db.commit()
    except Exception:
        db.rollback()
        raise
    db.refresh(group)
    return _public(db, group, user_id)


def update_preferences(db: Session, *, user_id: int, group_id: int, data: GroupPreferencesInput) -> GroupPublic:
    member = _member(db, group_id, user_id)
    if "custom_name" in data.model_fields_set:
        custom_name = data.custom_name.strip() if data.custom_name else None
        member.custom_name = custom_name or None
    if data.notifications_enabled is not None:
        member.notifications_enabled = data.notifications_enabled
    if data.pin_color_value is not None:
        member.pin_color_value = data.pin_color_value
    db.commit()
    return _public(db, group_repository.get_group(db, group_id), user_id)


def leave_group(db: Session, *, user_id: int, group_id: int) -> None:
    # Serialize repeated concurrent departures before emitting their event.
    member = db.scalar(select(GroupMember).where(
        GroupMember.group_id == group_id, GroupMember.user_id == user_id,
    ).with_for_update())
    if member is None:
        raise HTTPException(status_code=404, detail="모임을 찾을 수 없습니다.")
    try:
        db.delete(member)
        db.flush()
        notify_group_members(db, group_ids=[group_id], actor_id=user_id)
        db.commit()
    except Exception:
        db.rollback()
        raise
