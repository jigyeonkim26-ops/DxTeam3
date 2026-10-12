"""Authenticated, group-context comments for records."""
from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .db_models import User
from .group_db_models import GroupMember, MemoryGroup
from .notification_service import notify_record_author
from .record_models import Comment, Record, RecordGroup
from .records import require_db, require_visible_record


class CommentInput(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    content: str = Field(min_length=1, max_length=1000)
    parent_comment_id: int | None = Field(default=None, gt=0)
    group_id: int | None = Field(default=None, gt=0)


class CommentAuthorPublic(BaseModel):
    id: int
    name: str


class CommentGroupPublic(BaseModel):
    id: int
    name: str


class CommentPublic(BaseModel):
    id: int
    record_id: int
    group_id: int | None
    author_id: int
    parent_comment_id: int | None
    content: str
    created_at: datetime
    updated_at: datetime
    author: CommentAuthorPublic
    group: CommentGroupPublic | None


class CommentPage(BaseModel):
    items: list[CommentPublic]
    total: int
    offset: int
    limit: int


def comment_public(
    comment: Comment,
    author: User,
    group: MemoryGroup | None,
) -> CommentPublic:
    return CommentPublic(
        id=comment.id,
        record_id=comment.record_id,
        group_id=comment.group_id,
        author_id=comment.author_id,
        parent_comment_id=comment.parent_comment_id,
        content=comment.content,
        created_at=comment.created_at,
        updated_at=comment.updated_at,
        author=CommentAuthorPublic(id=author.id, name=author.nickname or "사용자"),
        group=(CommentGroupPublic(id=group.id, name=group.name) if group is not None else None),
    )


def _record_or_404(db: Session, record_id: int) -> Record:
    record = db.get(Record, record_id)
    if record is None:
        raise HTTPException(404, "기록을 찾을 수 없습니다.")
    return record


def _require_shared_group_context(
    db: Session,
    *,
    record_id: int,
    group_id: int,
    user_id: int,
) -> MemoryGroup:
    group = db.get(MemoryGroup, group_id)
    if group is None or db.get(RecordGroup, (record_id, group_id)) is None:
        raise HTTPException(404, "기록의 공유 모임을 찾을 수 없습니다.")
    if db.get(GroupMember, (group_id, user_id)) is None:
        raise HTTPException(403, "가입한 모임의 댓글만 볼 수 있습니다.")
    return group


def _comment_query(record_id: int):
    return select(Comment, User, MemoryGroup).join(
        User, User.id == Comment.author_id,
    ).outerjoin(MemoryGroup, MemoryGroup.id == Comment.group_id).where(
        Comment.record_id == record_id,
    )


def router(current_user):
    api = APIRouter(tags=["Comments"])

    @api.get("/records/{record_id}/comments", response_model=CommentPage)
    def list_comments(
        record_id: int,
        user=Depends(current_user),
        db: Session = Depends(require_db),
        group_id: int | None = Query(default=None, gt=0),
        scope: Literal["all"] | None = Query(default=None),
        offset: int = Query(default=0, ge=0),
        limit: int = Query(default=20, ge=1, le=100),
    ):
        if group_id is not None and scope is not None:
            raise HTTPException(422, "group_id와 scope는 함께 사용할 수 없습니다.")

        record = _record_or_404(db, record_id)
        if scope == "all":
            if record.author_id != user.id:
                raise HTTPException(403, "작성자만 전체 댓글을 볼 수 있습니다.")
            query = _comment_query(record_id)
        elif record.is_private:
            require_visible_record(db, record_id, user.id)
            if group_id is not None:
                raise HTTPException(422, "개인 기록에는 group_id를 사용할 수 없습니다.")
            query = _comment_query(record_id).where(Comment.group_id.is_(None))
        else:
            require_visible_record(db, record_id, user.id)
            if group_id is None:
                raise HTTPException(422, "공유 기록 댓글에는 group_id가 필요합니다.")
            _require_shared_group_context(
                db,
                record_id=record_id,
                group_id=group_id,
                user_id=user.id,
            )
            query = _comment_query(record_id).where(Comment.group_id == group_id)

        total = db.scalar(select(func.count()).select_from(query.subquery()))
        comments = db.execute(
            query.order_by(Comment.created_at, Comment.id).offset(offset).limit(limit)
        ).all()
        return CommentPage(
            items=[comment_public(comment, author, group) for comment, author, group in comments],
            total=total,
            offset=offset,
            limit=limit,
        )

    @api.post("/records/{record_id}/comments", response_model=CommentPublic, status_code=201)
    def create_comment(
        record_id: int,
        data: CommentInput,
        user=Depends(current_user),
        db: Session = Depends(require_db),
    ):
        record = _record_or_404(db, record_id)
        group: MemoryGroup | None = None
        if record.is_private:
            require_visible_record(db, record_id, user.id)
            if data.group_id is not None:
                raise HTTPException(422, "개인 기록 댓글에는 group_id를 지정할 수 없습니다.")
        else:
            require_visible_record(db, record_id, user.id)
            if data.group_id is None:
                raise HTTPException(422, "공유 기록 댓글에는 group_id가 필요합니다.")
            group = _require_shared_group_context(
                db,
                record_id=record_id,
                group_id=data.group_id,
                user_id=user.id,
            )

        if data.parent_comment_id is not None:
            parent = db.scalar(select(Comment).where(
                Comment.id == data.parent_comment_id,
                Comment.record_id == record_id,
            ))
            if parent is None:
                raise HTTPException(404, "부모 댓글을 찾을 수 없습니다.")
            if parent.group_id != data.group_id:
                raise HTTPException(422, "부모 댓글과 같은 모임에서만 답글을 작성할 수 있습니다.")

        comment = Comment(
            record_id=record_id,
            group_id=data.group_id,
            author_id=user.id,
            content=data.content,
            parent_comment_id=data.parent_comment_id,
        )
        db.add(comment)
        try:
            notify_record_author(
                db,
                record_id=record_id,
                actor_id=user.id,
                event="COMMENT",
                parent_comment_id=data.parent_comment_id,
            )
            db.commit()
        except IntegrityError:
            db.rollback()
            raise HTTPException(409, "댓글을 저장하지 못했습니다. 다시 시도해 주세요.") from None
        db.refresh(comment)
        return comment_public(comment, user, group)

    @api.delete("/records/{record_id}/comments/{comment_id}", status_code=204)
    def delete_comment(
        record_id: int,
        comment_id: int,
        user=Depends(current_user),
        db: Session = Depends(require_db),
    ):
        require_visible_record(db, record_id, user.id)
        comment = db.scalar(select(Comment).where(
            Comment.id == comment_id, Comment.record_id == record_id,
        ).with_for_update())
        if comment is None:
            raise HTTPException(404, "댓글을 찾을 수 없습니다.")
        if comment.author_id != user.id:
            raise HTTPException(403, "본인이 작성한 댓글만 삭제할 수 있습니다.")
        if db.scalar(select(Comment.id).where(Comment.parent_comment_id == comment_id).limit(1)) is not None:
            raise HTTPException(409, "답글이 있는 댓글은 답글을 먼저 삭제해야 합니다.")
        db.delete(comment)
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            raise HTTPException(409, "댓글을 삭제하지 못했습니다. 다시 시도해 주세요.") from None
        return Response(status_code=204)

    return api
