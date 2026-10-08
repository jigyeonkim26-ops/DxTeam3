"""Authenticated comments using the existing record visibility rules."""
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .db_models import User
from .record_models import Comment
from .notification_service import notify_record_author
from .records import require_db, require_visible_record


class CommentInput(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    content: str = Field(min_length=1, max_length=1000)
    parent_comment_id: int | None = Field(default=None, gt=0)


class CommentAuthorPublic(BaseModel):
    id: int
    name: str


class CommentPublic(BaseModel):
    id: int
    record_id: int
    author_id: int
    parent_comment_id: int | None
    content: str
    created_at: datetime
    updated_at: datetime
    author: CommentAuthorPublic


class CommentPage(BaseModel):
    items: list[CommentPublic]
    total: int
    offset: int
    limit: int


def comment_public(comment: Comment, author: User) -> CommentPublic:
    return CommentPublic(
        id=comment.id,
        record_id=comment.record_id,
        author_id=comment.author_id,
        parent_comment_id=comment.parent_comment_id,
        content=comment.content,
        created_at=comment.created_at,
        updated_at=comment.updated_at,
        author=CommentAuthorPublic(id=author.id, name=author.nickname or "사용자"),
    )


def router(current_user):
    api = APIRouter(tags=["Comments"])

    @api.get("/records/{record_id}/comments", response_model=CommentPage)
    def list_comments(
        record_id: int, user=Depends(current_user), db: Session = Depends(require_db),
        offset: int = Query(default=0, ge=0), limit: int = Query(default=20, ge=1, le=100),
    ):
        require_visible_record(db, record_id, user.id)
        query = select(Comment, User).join(User, User.id == Comment.author_id).where(
            Comment.record_id == record_id)
        total = db.scalar(select(func.count()).select_from(query.subquery()))
        comments = db.execute(query.order_by(Comment.created_at, Comment.id)
                              .offset(offset).limit(limit)).all()
        return CommentPage(items=[comment_public(comment, author) for comment, author in comments],
                           total=total, offset=offset, limit=limit)

    @api.post("/records/{record_id}/comments", response_model=CommentPublic, status_code=201)
    def create_comment(
        record_id: int, data: CommentInput,
        user=Depends(current_user), db: Session = Depends(require_db),
    ):
        require_visible_record(db, record_id, user.id)
        if data.parent_comment_id is not None:
            parent = db.scalar(select(Comment.id).where(
                Comment.id == data.parent_comment_id, Comment.record_id == record_id))
            if parent is None:
                raise HTTPException(404, "부모 댓글을 찾을 수 없습니다.")
        comment = Comment(record_id=record_id, author_id=user.id, **data.model_dump())
        db.add(comment)
        try:
            notify_record_author(db, record_id=record_id, actor_id=user.id, event="COMMENT",
                                 parent_comment_id=data.parent_comment_id)
            db.commit()
        except IntegrityError:
            db.rollback()
            raise HTTPException(409, "댓글을 저장하지 못했습니다. 다시 시도해 주세요.") from None
        db.refresh(comment)
        return comment_public(comment, user)

    @api.delete("/records/{record_id}/comments/{comment_id}", status_code=204)
    def delete_comment(
        record_id: int, comment_id: int,
        user=Depends(current_user), db: Session = Depends(require_db),
    ):
        require_visible_record(db, record_id, user.id)
        comment = db.scalar(select(Comment).where(
            Comment.id == comment_id, Comment.record_id == record_id).with_for_update())
        if comment is None:
            raise HTTPException(404, "댓글을 찾을 수 없습니다.")
        if comment.author_id != user.id:
            raise HTTPException(403, "본인이 작성한 댓글만 삭제할 수 있습니다.")
        if db.scalar(select(Comment.id).where(Comment.parent_comment_id == comment_id).limit(1)) is not None:
            raise HTTPException(409, "답글이 있는 댓글은 답글 삭제 후 삭제할 수 있습니다.")
        db.delete(comment)
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            raise HTTPException(409, "댓글을 삭제하지 못했습니다. 다시 시도해 주세요.") from None
        return Response(status_code=204)

    return api
