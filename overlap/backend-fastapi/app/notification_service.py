from sqlalchemy import select
from sqlalchemy.orm import Session

from .notification_models import Notification, NotificationSettings
from .record_models import Comment, GroupMember, Record, RecordGroup


def notify_record_author(db: Session, *, record_id: int, actor_id: int, event: str, parent_comment_id: int | None = None):
    record = db.get(Record, record_id)
    if record is None:
        return
    recipients = {record.author_id}
    if parent_comment_id is not None:
        parent = db.get(Comment, parent_comment_id)
        if parent is not None and parent.record_id == record_id:
            can_view = (record.is_private and parent.author_id == record.author_id) or (
                not record.is_private and db.scalar(select(GroupMember.user_id).join(
                    RecordGroup, RecordGroup.group_id == GroupMember.group_id
                ).where(RecordGroup.record_id == record_id,
                        GroupMember.user_id == parent.author_id).limit(1)) is not None
            )
            if can_view:
                recipients.add(parent.author_id)
    flag = "reactions_enabled" if event == "LIKE" else "comments_replies_enabled"
    for recipient_id in recipients - {actor_id}:
        settings = db.get(NotificationSettings, recipient_id)
        if settings is not None and not getattr(settings, flag):
            continue
        db.add(Notification(
            user_id=recipient_id, type=event,
            title="새 좋아요" if event == "LIKE" else "새 댓글",
            message="기록에 좋아요가 추가되었습니다." if event == "LIKE" else "기록에 댓글이 작성되었습니다.",
            reference_type="RECORD", reference_id=record_id, is_read=False,
        ))


def notify_group_members(db: Session, *, group_ids: list[int], actor_id: int,
                         record_id: int | None = None):
    """Deduplicate recipients for one event; commit with the originating change."""
    if not group_ids:
        return
    recipients = set(db.scalars(select(GroupMember.user_id).where(
        GroupMember.group_id.in_(group_ids), GroupMember.user_id != actor_id,
        GroupMember.notifications_enabled.is_(True),
    )))
    flag = "new_group_records_enabled" if record_id is not None else "group_updates_enabled"
    for recipient_id in recipients:
        settings = db.get(NotificationSettings, recipient_id)
        if settings is not None and not getattr(settings, flag):
            continue
        db.add(Notification(
            user_id=recipient_id, type="GROUP_RECORD" if record_id is not None else "GROUP_UPDATE",
            title="새 모임 기록" if record_id is not None else "모임 업데이트",
            message="모임에 새 기록이 공유되었습니다." if record_id is not None else "모임 정보 또는 가입자가 변경되었습니다.",
            reference_type="RECORD" if record_id is not None else "GROUP",
            reference_id=record_id if record_id is not None else group_ids[0], is_read=False,
        ))
