import secrets
import string

from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .group_db_models import MemoryGroup
from .models import GroupCreated, GroupPublic
from . import group_repository


INVITE_CODE_LENGTH = 12
INVITE_CODE_ALPHABET = string.ascii_uppercase + string.digits


def _generate_invite_code(db: Session) -> str:
    for _ in range(20):
        code = "".join(
            secrets.choice(INVITE_CODE_ALPHABET)
            for _ in range(INVITE_CODE_LENGTH)
        )

        if not group_repository.invite_code_exists(db, code):
            return code

    raise RuntimeError("고유한 초대 코드를 생성하지 못했습니다.")


def _to_group_public(
    db: Session,
    group: MemoryGroup,
    user_id: int | None = None,
) -> GroupPublic:
    member = (
        group_repository.get_member(db, group_id=group.id, user_id=user_id)
        if user_id is not None else None
    )
    return GroupPublic(
        id=group.id,
        name=group.name,
        display_name=(member.custom_name or group.name) if member else group.name,
        member_count=group_repository.count_members(db, group.id),
        description=group.description,
        visibility=group.visibility,
        notifications_enabled=member.notifications_enabled if member else True,
        pin_color_value=member.pin_color_value if member else None,
    )


def create_group(
    db: Session,
    *,
    user_id: int,
    name: str,
    description: str | None = None,
    visibility: str = "INVITED_ONLY",
) -> GroupCreated:
    invite_code = _generate_invite_code(db)

    try:
        group = group_repository.create_group(
            db,
            name=name,
            invite_code=invite_code,
            description=description,
            visibility=visibility,
        )

        group_repository.add_member(
            db,
            group_id=group.id,
            user_id=user_id,
        )

        db.commit()
        db.refresh(group)

    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="모임을 생성하는 중 중복 데이터가 발생했습니다.",
        )

    except Exception:
        db.rollback()
        raise

    public = _to_group_public(db, group, user_id)

    return GroupCreated(
        **public.model_dump(),
        invite_code=group.invite_code,
    )


def join_group(
    db: Session,
    *,
    user_id: int,
    invite_code: str,
) -> GroupPublic:
    normalized_code = invite_code.strip().upper()

    group = group_repository.get_group_by_invite_code(
        db,
        normalized_code,
    )

    if group is None:
        raise HTTPException(
            status_code=404,
            detail="초대 코드를 확인해 주세요.",
        )

    if not group.invite_enabled:
        raise HTTPException(
            status_code=403,
            detail="현재 사용할 수 없는 초대 코드입니다.",
        )

    if group_repository.is_member(
        db,
        group_id=group.id,
        user_id=user_id,
    ):
        raise HTTPException(
            status_code=409,
            detail="이미 가입한 모임입니다.",
        )

    try:
        group_repository.add_member(
            db,
            group_id=group.id,
            user_id=user_id,
        )

        db.commit()

    except IntegrityError:
        db.rollback()
        raise HTTPException(
            status_code=409,
            detail="이미 가입한 모임입니다.",
        )

    except Exception:
        db.rollback()
        raise

    return _to_group_public(db, group, user_id)


def list_groups(
    db: Session,
    *,
    user_id: int,
) -> list[GroupPublic]:
    groups = group_repository.list_groups_by_user(
        db,
        user_id,
    )

    return [
        _to_group_public(db, group, user_id)
        for group in groups
    ]


def get_invite(
    db: Session,
    *,
    user_id: int,
    group_id: int,
) -> str:
    group = group_repository.get_group(
        db,
        group_id,
    )

    if group is None:
        raise HTTPException(
            status_code=404,
            detail="모임을 찾을 수 없습니다.",
        )

    if not group_repository.is_member(
        db,
        group_id=group_id,
        user_id=user_id,
    ):
        raise HTTPException(
            status_code=404,
            detail="가입한 모임을 찾을 수 없습니다.",
        )

    if not group.invite_code:
        raise HTTPException(
            status_code=404,
            detail="현재 사용할 수 있는 초대 코드가 없습니다.",
        )

    return group.invite_code
