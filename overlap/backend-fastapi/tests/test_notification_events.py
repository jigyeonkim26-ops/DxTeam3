import pytest
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.notification_models import Notification, NotificationSettings
from app.record_models import GroupMember, MemoryGroup, Record
from test_notifications import call
from test_records import create, world


def items(world, user, kind=None):
    rows = call(world, "GET", user=user).json()["items"]
    return [n for n in rows if kind is None or n["type"] == kind]


@pytest.mark.parametrize("global_enabled,group_enabled", [(True, True), (False, True), (True, False), (False, False)])
def test_group_record_settings_private_and_self(world, global_enabled, group_enabled):
    with Session(world[1]) as db:
        db.add(NotificationSettings(user_id=2, new_group_records_enabled=global_enabled))
        db.get(GroupMember, (10, 2)).notifications_enabled = group_enabled
        db.commit()
    assert create(world, private=True).status_code == 201
    assert items(world, 2) == []
    response = create(world)
    assert response.status_code == 201
    notifications = items(world, 2)
    assert len(notifications) == int(global_enabled and group_enabled)
    if notifications:
        assert notifications[0]["type"] == "GROUP_RECORD"
        assert notifications[0]["reference_type"] == "RECORD"
        assert notifications[0]["reference_id"] == response.json()["id"]
        assert "테스트1" in notifications[0]["message"]
        assert "실제 가입 모임" in notifications[0]["message"]
    assert items(world, 1) == []
    assert items(world, 3) == []


def test_group_record_deduplicates_across_allowed_memberships(world):
    with Session(world[1]) as db:
        db.add_all([GroupMember(group_id=20, user_id=1), GroupMember(group_id=20, user_id=2)])
        db.get(GroupMember, (10, 2)).notifications_enabled = False
        db.commit()
    assert create(world, groups=[10, 20, 20]).status_code == 201
    assert len(items(world, 2, "GROUP_RECORD")) == 1
    assert create(world, groups=[10, 20]).status_code == 201
    assert len(items(world, 2, "GROUP_RECORD")) == 2


def test_group_record_failure_rolls_back_notifications_and_record(world, monkeypatch):
    import app.records as records
    from app.notification_service import notify_group_members

    def fail(*args, **kwargs):
        notify_group_members(*args, **kwargs)
        raise RuntimeError("simulated failure")

    monkeypatch.setattr(records, "notify_group_members", fail)
    assert create(world).status_code == 503
    with Session(world[1]) as db:
        assert db.scalar(select(func.count()).select_from(Record)) == 0
        assert db.scalar(select(func.count()).select_from(Notification)) == 0
    assert world[2].objects == {}


def test_reply_notifies_distinct_authors_and_respects_recipient_settings(world):
    with Session(world[1]) as db:
        db.add(GroupMember(group_id=10, user_id=3))
        db.commit()
    record_id = create(world).json()["id"]
    path = f"/records/{record_id}/comments"
    parent = call(world, "POST", path, user=2, json={"content": "parent"}).json()
    assert "테스트2" in items(world, 1, "COMMENT")[0]["message"]
    assert call(world, "POST", path, user=3, json={"content": "reply", "parent_comment_id": parent["id"]}).status_code == 201
    assert len(items(world, 1, "COMMENT")) == 2
    assert len(items(world, 2, "COMMENT")) == 1
    assert items(world, 3, "COMMENT") == []
    assert call(world, "PATCH", "/notifications/settings", user=2,
                json={"comments_replies_enabled": False}).status_code == 200
    assert call(world, "POST", path, user=1, json={"content": "another", "parent_comment_id": parent["id"]}).status_code == 201
    assert len(items(world, 2, "COMMENT")) == 1
    assert len(items(world, 1, "COMMENT")) == 2


def test_reply_same_author_deduplicated_and_separate_replies_are_new_events(world):
    record_id = create(world).json()["id"]
    path = f"/records/{record_id}/comments"
    parent = call(world, "POST", path, json={"content": "parent"}).json()
    for count in (1, 2):
        assert call(world, "POST", path, user=2, json={"content": "reply", "parent_comment_id": parent["id"]}).status_code == 201
        assert len(items(world, 1, "COMMENT")) == count
    assert call(world, "POST", path, json={"content": "self", "parent_comment_id": parent["id"]}).status_code == 201
    assert len(items(world, 1, "COMMENT")) == 2


def test_reply_to_own_comment_and_revoked_parent_author(world):
    record_id = create(world).json()["id"]
    path = f"/records/{record_id}/comments"
    parent = call(world, "POST", path, user=2, json={"content": "parent"}).json()
    assert call(world, "POST", path, user=2, json={"content": "self reply", "parent_comment_id": parent["id"]}).status_code == 201
    assert items(world, 2, "COMMENT") == []
    assert len(items(world, 1, "COMMENT")) == 2
    with Session(world[1]) as db:
        db.delete(db.get(GroupMember, (10, 2)))
        db.commit()
    assert call(world, "POST", path, json={"content": "reply", "parent_comment_id": parent["id"]}).status_code == 201
    assert items(world, 2, "COMMENT") == []


def test_reply_failure_rolls_back_comment_and_notifications(world, monkeypatch):
    import app.comments as comments
    from app.notification_service import notify_record_author
    from app.record_models import Comment

    record_id = create(world).json()["id"]
    path = f"/records/{record_id}/comments"
    parent = call(world, "POST", path, json={"content": "parent"}).json()

    def fail(db, **kwargs):
        notify_record_author(db, **kwargs)
        db.flush()
        from sqlalchemy.exc import IntegrityError
        raise IntegrityError("simulated", {}, None)

    monkeypatch.setattr(comments, "notify_record_author", fail)
    assert call(world, "POST", path, user=2, json={"content": "reply", "parent_comment_id": parent["id"]}).status_code == 409
    assert items(world, 1, "COMMENT") == []
    with Session(world[1]) as db:
        assert db.scalar(select(func.count()).select_from(Comment)) == 1


def test_group_join_update_leave_and_noop_events(world):
    with Session(world[1]) as db:
        db.get(MemoryGroup, 10).invite_code = "TESTJOINCODE"
        db.commit()
    assert call(world, "POST", "/groups/join", user=3, json={"invite_code": "TESTJOINCODE"}).status_code == 200
    assert call(world, "POST", "/groups/join", user=3, json={"invite_code": "TESTJOINCODE"}).status_code == 409
    assert len(items(world, 1, "GROUP_UPDATE")) == 1
    assert items(world, 3) == []
    payload = {"description": "updated", "visibility": "INVITED_ONLY"}
    assert call(world, "PUT", "/groups/10", json=payload).status_code == 200
    assert call(world, "PUT", "/groups/10", json=payload).status_code == 200
    assert len(items(world, 2, "GROUP_UPDATE")) == 2
    assert call(world, "PATCH", "/groups/10/preferences", json={"custom_name": "personal"}).status_code == 200
    assert len(items(world, 2, "GROUP_UPDATE")) == 2
    assert call(world, "PATCH", "/notifications/settings", user=2, json={"group_updates_enabled": False}).status_code == 200
    assert call(world, "DELETE", "/groups/10/members/me", user=3).status_code == 204
    assert call(world, "DELETE", "/groups/10/members/me", user=3).status_code == 404
    assert len(items(world, 1, "GROUP_UPDATE")) == 2
    assert len(items(world, 2, "GROUP_UPDATE")) == 2
    assert len(items(world, 3, "GROUP_UPDATE")) == 1


@pytest.mark.parametrize("global_enabled,group_enabled", [(True, True), (False, True), (True, False)])
def test_group_updates_respect_both_settings_and_reject_nonmembers(world, global_enabled, group_enabled):
    with Session(world[1]) as db:
        db.add(NotificationSettings(user_id=2, group_updates_enabled=global_enabled))
        db.get(GroupMember, (10, 2)).notifications_enabled = group_enabled
        db.commit()
    payload = {"description": "changed", "visibility": "INVITED_ONLY"}
    assert call(world, "PUT", "/groups/10", user=3, json=payload).status_code == 404
    assert items(world, 2) == []
    assert call(world, "PUT", "/groups/10", json=payload).status_code == 200
    assert len(items(world, 2, "GROUP_UPDATE")) == int(global_enabled and group_enabled)
    assert items(world, 1) == []
    assert items(world, 3) == []


@pytest.mark.parametrize("operation", ["join", "leave", "update"])
def test_group_event_failure_rolls_back_original_change(world, monkeypatch, operation):
    from app import group_service, group_management_service
    with Session(world[1]) as db:
        db.get(MemoryGroup, 10).invite_code = "TESTJOINCODE"
        db.commit()

    def fail(*args, **kwargs):
        from app.notification_service import notify_group_members
        notify_group_members(*args, **kwargs)
        raise RuntimeError("simulated failure")

    target = group_service if operation == "join" else group_management_service
    monkeypatch.setattr(target, "notify_group_members", fail)
    with pytest.raises(RuntimeError):
        if operation == "join":
            call(world, "POST", "/groups/join", user=3, json={"invite_code": "TESTJOINCODE"})
        elif operation == "leave":
            call(world, "DELETE", "/groups/10/members/me", user=2)
        else:
            call(world, "PUT", "/groups/10", json={"description": "changed", "visibility": "INVITED_ONLY"})
    with Session(world[1]) as db:
        assert db.get(GroupMember, (10, 3)) is None
        assert db.get(GroupMember, (10, 2)) is not None
        assert db.get(MemoryGroup, 10).description is None
        assert db.scalar(select(func.count()).select_from(Notification)) == 0
