from sqlalchemy import func, select
from sqlalchemy.orm import Session

from .group_db_models import GroupMember, MemoryGroup


def create_group(
    db: Session,
    *,
    name: str,
    invite_code: str,
    description: str | None = None,
    visibility: str = "INVITED_ONLY",
) -> MemoryGroup:
    group = MemoryGroup(
        name=name,
        description=description,
        visibility=visibility,
        invite_code=invite_code,
        invite_enabled=True,
    )

    db.add(group)
    db.flush()

    return group


def add_member(
    db: Session,
    *,
    group_id: int,
    user_id: int,
) -> GroupMember:
    member = GroupMember(
        group_id=group_id,
        user_id=user_id,
    )

    db.add(member)
    db.flush()

    return member


def get_group(
    db: Session,
    group_id: int,
) -> MemoryGroup | None:
    return db.get(MemoryGroup, group_id)


def get_group_by_invite_code(
    db: Session,
    invite_code: str,
) -> MemoryGroup | None:
    return db.scalar(
        select(MemoryGroup).where(
            MemoryGroup.invite_code == invite_code
        )
    )


def is_member(
    db: Session,
    *,
    group_id: int,
    user_id: int,
) -> bool:
    member = db.get(
        GroupMember,
        {
            "group_id": group_id,
            "user_id": user_id,
        },
    )

    return member is not None


def get_member(db: Session, *, group_id: int, user_id: int) -> GroupMember | None:
    return db.get(GroupMember, {"group_id": group_id, "user_id": user_id})


def count_members(
    db: Session,
    group_id: int,
) -> int:
    count = db.scalar(
        select(func.count())
        .select_from(GroupMember)
        .where(GroupMember.group_id == group_id)
    )

    return int(count or 0)


def list_groups_by_user(
    db: Session,
    user_id: int,
) -> list[MemoryGroup]:
    statement = (
        select(MemoryGroup)
        .join(
            GroupMember,
            GroupMember.group_id == MemoryGroup.id,
        )
        .where(GroupMember.user_id == user_id)
        .order_by(MemoryGroup.created_at.desc())
    )

    return list(db.scalars(statement).all())


def invite_code_exists(
    db: Session,
    invite_code: str,
) -> bool:
    group_id = db.scalar(
        select(MemoryGroup.id).where(
            MemoryGroup.invite_code == invite_code
        )
    )

    return group_id is not None
