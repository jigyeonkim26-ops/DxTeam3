"""Authenticated comments with server-owned shared-group scope."""
from datetime import datetime
import hashlib
import mimetypes
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import exists, func, or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from .db_models import User
from .group_db_models import GroupMember, MemoryGroup
from .notification_service import notify_record_author
from .object_storage import get_object_storage
from .record_models import Comment, CommentGroup, Record, RecordGroup
from .records import require_db, require_visible_record


class CommentInput(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    content: str = Field(min_length=1, max_length=1000)
    parent_comment_id: int | None = Field(default=None, gt=0)
    group_id: int | None = Field(default=None, gt=0)


class CommentAuthorPublic(BaseModel):
    id: int
    name: str
    profile_image_url: str | None = None


class CommentGroupPublic(BaseModel):
    id: int
    name: str


class CommentPublic(BaseModel):
    id: int
    record_id: int
    group_id: int | None
    group_ids: list[int]
    is_global: bool
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


def _comment_group_ids(db: Session, comment_ids: list[int]) -> dict[int, list[int]]:
    result = {comment_id: [] for comment_id in comment_ids}
    if not result:
        return result
    for comment_id, group_id in db.execute(select(CommentGroup.comment_id, CommentGroup.group_id).where(
        CommentGroup.comment_id.in_(comment_ids)).order_by(CommentGroup.comment_id, CommentGroup.group_id)):
        result[comment_id].append(group_id)
    return result


def _shared_group_ids_for_user(db: Session, *, record_id: int, user_id: int) -> list[int]:
    return list(db.scalars(select(RecordGroup.group_id).join(
        GroupMember, GroupMember.group_id == RecordGroup.group_id).where(
        RecordGroup.record_id == record_id, GroupMember.user_id == user_id).order_by(RecordGroup.group_id)))


def _linked_to_any_group(group_ids: list[int]):
    return exists(select(CommentGroup.comment_id).where(
        CommentGroup.comment_id == Comment.id, CommentGroup.group_id.in_(group_ids)))


def _compat_group_id(group_ids: list[int]) -> int | None:
    return group_ids[0] if len(group_ids) == 1 else None


def _record_or_404(db: Session, record_id: int) -> Record:
    record = db.get(Record, record_id)
    if record is None:
        raise HTTPException(404, "Record not found.")
    return record


def _require_shared_group_context(db: Session, *, record_id: int, group_id: int, user_id: int) -> None:
    if db.get(RecordGroup, (record_id, group_id)) is None:
        raise HTTPException(404, "The record is not shared with that group.")
    if db.get(GroupMember, (group_id, user_id)) is None:
        raise HTTPException(403, "You are not a member of that group.")


def _comment_query(record_id: int):
    return select(Comment, User, MemoryGroup).join(User, User.id == Comment.author_id).outerjoin(
        MemoryGroup, MemoryGroup.id == Comment.group_id).where(Comment.record_id == record_id)


def _comment_public(comment: Comment, author: User, group: MemoryGroup | None, group_ids: list[int]) -> CommentPublic:
    public = CommentPublic(id=comment.id, record_id=comment.record_id, group_id=comment.group_id,
        group_ids=group_ids, is_global=comment.is_global, author_id=comment.author_id,
        parent_comment_id=comment.parent_comment_id, content=comment.content,
        created_at=comment.created_at, updated_at=comment.updated_at,
        author=CommentAuthorPublic(id=author.id, name=author.nickname or "User"),
        group=CommentGroupPublic(id=group.id, name=group.name) if group else None)
    if author.profile_image_key:
        version = hashlib.sha256(author.profile_image_key.encode()).hexdigest()[:16]
        public.author.profile_image_url = f"/records/{comment.record_id}/comments/{comment.id}/author-photo?v={version}"
    return public


def router(current_user):
    api = APIRouter(tags=["Comments"])

    @api.get("/records/{record_id}/comments", response_model=CommentPage)
    def list_comments(record_id: int, user=Depends(current_user), db: Session = Depends(require_db),
                      group_id: int | None = Query(default=None, gt=0), scope: Literal["all"] | None = Query(default=None),
                      offset: int = Query(default=0, ge=0), limit: int = Query(default=20, ge=1, le=100)):
        if group_id is not None and scope is not None:
            raise HTTPException(422, "group_id and scope cannot be used together.")
        record = _record_or_404(db, record_id)
        if scope == "all":
            if record.author_id != user.id:
                raise HTTPException(403, "Only the record author may view all comments.")
            query = _comment_query(record_id)
        elif record.is_private:
            require_visible_record(db, record_id, user.id)
            if group_id is not None:
                raise HTTPException(422, "Private-record comments do not use group_id.")
            query = _comment_query(record_id).where(Comment.group_id.is_(None))
        else:
            groups = _shared_group_ids_for_user(db, record_id=record_id, user_id=user.id)
            if not groups:
                raise HTTPException(403, "No shared comment group is available.")
            require_visible_record(db, record_id, user.id)
            if group_id is not None:
                _require_shared_group_context(db, record_id=record_id, group_id=group_id, user_id=user.id)
                groups = [group_id]
            query = _comment_query(record_id).where(or_(_linked_to_any_group(groups), Comment.is_global.is_(True)))
        total = db.scalar(select(func.count()).select_from(query.subquery()))
        rows = db.execute(query.order_by(Comment.created_at, Comment.id).offset(offset).limit(limit)).all()
        group_ids = _comment_group_ids(db, [comment.id for comment, _, _ in rows])
        return CommentPage(items=[_comment_public(comment, author, group, group_ids.get(comment.id, []))
                                  for comment, author, group in rows], total=total, offset=offset, limit=limit)

    @api.post("/records/{record_id}/comments", response_model=CommentPublic, status_code=201)
    def create_comment(record_id: int, data: CommentInput, user=Depends(current_user), db: Session = Depends(require_db)):
        record = _record_or_404(db, record_id)
        parent = db.scalar(select(Comment).where(Comment.id == data.parent_comment_id,
            Comment.record_id == record_id)) if data.parent_comment_id else None
        if data.parent_comment_id and parent is None:
            raise HTTPException(404, "Parent comment not found.")
        is_global = False
        comment_group_ids: list[int] = []
        if record.is_private:
            require_visible_record(db, record_id, user.id)
            if data.group_id is not None:
                raise HTTPException(422, "Private-record comments do not use group_id.")
        else:
            visible = _shared_group_ids_for_user(db, record_id=record_id, user_id=user.id)
            if parent is None:
                is_global = record.author_id == user.id
                comment_group_ids = [] if is_global else visible
            elif parent.is_global:
                is_global = record.author_id == user.id
                comment_group_ids = [] if is_global else visible
            else:
                parent_groups = _comment_group_ids(db, [parent.id]).get(parent.id, [])
                if parent_groups:
                    comment_group_ids = parent_groups if record.author_id == user.id else [g for g in parent_groups if g in set(visible)]
                elif record.author_id != user.id:
                    raise HTTPException(403, "Only the record author may reply to legacy comments.")
            if not is_global and not comment_group_ids and record.author_id != user.id:
                raise HTTPException(403, "No shared comment group is available.")
            data.group_id = None if is_global else _compat_group_id(comment_group_ids)
            require_visible_record(db, record_id, user.id)
        comment = Comment(record_id=record_id, group_id=data.group_id, is_global=is_global, author_id=user.id,
            content=data.content, parent_comment_id=data.parent_comment_id)
        db.add(comment)
        try:
            db.flush()
            for group_id in comment_group_ids:
                db.add(CommentGroup(comment_id=comment.id, group_id=group_id))
            notify_record_author(db, record_id=record_id, actor_id=user.id, event="COMMENT", parent_comment_id=data.parent_comment_id)
            db.commit()
        except IntegrityError:
            db.rollback()
            raise HTTPException(409, "Could not save comment. Please try again.") from None
        db.refresh(comment)
        return _comment_public(comment, db.get(User, user.id), db.get(MemoryGroup, comment.group_id) if comment.group_id else None, comment_group_ids)

    @api.get("/records/{record_id}/comments/{comment_id}/author-photo")
    def comment_author_photo(record_id: int, comment_id: int, user=Depends(current_user), db: Session = Depends(require_db)):
        require_visible_record(db, record_id, user.id)
        author = db.scalar(select(User).join(Comment, Comment.author_id == User.id).where(Comment.id == comment_id, Comment.record_id == record_id))
        if author is None or author.profile_image_key is None:
            raise HTTPException(404, "Comment author photo not found.")
        object_key = author.profile_image_key
        media_type = mimetypes.guess_type(object_key)[0] or "application/octet-stream"
        db.rollback()
        body = get_object_storage().download(object_key)
        def chunks():
            try:
                while chunk := body.read(64 * 1024):
                    yield chunk
            finally:
                body.close()
        return StreamingResponse(chunks(), media_type=media_type,
            headers={"Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff"})

    @api.delete("/records/{record_id}/comments/{comment_id}", status_code=204)
    def delete_comment(record_id: int, comment_id: int, user=Depends(current_user), db: Session = Depends(require_db)):
        require_visible_record(db, record_id, user.id)
        comment = db.scalar(select(Comment).where(Comment.id == comment_id, Comment.record_id == record_id).with_for_update())
        if comment is None:
            raise HTTPException(404, "Comment not found.")
        if comment.author_id != user.id:
            raise HTTPException(403, "Only the comment author may delete it.")
        if db.scalar(select(Comment.id).where(Comment.parent_comment_id == comment_id).limit(1)) is not None:
            raise HTTPException(409, "Delete replies before deleting their parent comment.")
        db.delete(comment)
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            raise HTTPException(409, "Could not delete comment.") from None
        return Response(status_code=204)

    return api
