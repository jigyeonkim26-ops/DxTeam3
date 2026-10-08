import pytest
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.notification_models import Notification, NotificationSettings
from test_records import create, world


def call(world, method, path="/notifications", user=1, **kwargs):
    return world[0].request(method, path, headers=world[3][user], **kwargs)


def seed(world):
    with Session(world[1]) as db:
        rows = [Notification(user_id=u, type="LIKE", title="Test", message="Test",
                             is_read=False, reference_type="RECORD", reference_id=123)
                for u in (1, 1, 2)]
        db.add_all(rows)
        db.commit()
        return [n.id for n in rows]


def test_personal_list_pagination_count_and_read_operations(world):
    ids = seed(world)
    listed = call(world, "GET").json()
    assert listed["total"] == 2
    assert [n["id"] for n in listed["items"]] == ids[:2][::-1]
    assert all("user_id" not in n for n in listed["items"])
    page = call(world, "GET", "/notifications?limit=1&offset=1&user_id=2").json()
    assert page == dict(items=[listed["items"][1]], total=2, offset=1, limit=1)
    assert call(world, "GET", "/notifications/unread-count").json() == {"unread_count": 2}
    for _ in range(2):
        response = call(world, "PATCH", f"/notifications/{ids[0]}/read")
        assert response.status_code == 200 and response.json()["is_read"] is True
    assert call(world, "GET", "/notifications/unread-count").json() == {"unread_count": 1}
    for _ in range(2):
        assert call(world, "PATCH", "/notifications/read-all").json() == {"unread_count": 0}
    assert call(world, "GET", "/notifications/unread-count", user=2).json() == {"unread_count": 1}


def test_other_users_and_missing_notifications_return_404(world):
    ids = seed(world)
    assert call(world, "PATCH", f"/notifications/{ids[2]}/read?user_id=2").status_code == 404
    assert call(world, "PATCH", "/notifications/999999/read").status_code == 404
    assert call(world, "GET", user=3).json()["items"] == []
    assert call(world, "GET", "/notifications/unread-count", user=2).json()["unread_count"] == 1


def test_settings_defaults_partial_update_isolation_and_validation(world):
    path = "/notifications/settings"
    defaults = call(world, "GET", path)
    assert defaults.status_code == 200
    assert defaults.json()["reactions_enabled"] is True
    with Session(world[1]) as db:
        assert db.get(NotificationSettings, 1) is None  # GET does not write defaults.
    patched = call(world, "PATCH", path + "?user_id=2", json={
        "reactions_enabled": False, "quiet_start_time": "22:00:00", "quiet_end_time": "07:00:00",
    })
    assert patched.status_code == 200
    assert patched.json()["reactions_enabled"] is False
    assert patched.json()["quiet_start_time"] == "22:00:00"
    assert patched.json()["updated_at"]
    changed = call(world, "PATCH", path, json={"comments_replies_enabled": False}).json()
    assert changed["reactions_enabled"] is False
    assert changed["quiet_start_time"] == "22:00:00"
    assert call(world, "GET", path, user=2).json()["reactions_enabled"] is True
    for payload in ({"user_id": 2}, {"reactions_enabled": None}, {"quiet_start_time": "bad"}):
        assert call(world, "PATCH", path, json=payload).status_code == 422
    assert call(world, "PATCH", path, json={"quiet_start_time": None}).json()["quiet_start_time"] is None


@pytest.mark.parametrize("event,flag", [("likes", "reactions_enabled"), ("comments", "comments_replies_enabled")])
@pytest.mark.parametrize("enabled", [True, False])
def test_event_notifications_respect_recipient_settings(world, event, flag, enabled):
    record_id = create(world).json()["id"]
    assert call(world, "PATCH", "/notifications/settings", json={flag: enabled}).status_code == 200
    response = call(world, "POST", f"/records/{record_id}/{event}", user=2,
                    **({"json": {"content": "A comment"}} if event == "comments" else {}))
    assert response.status_code == (201 if event == "comments" else 200)
    listed = call(world, "GET").json()
    assert listed["total"] == int(enabled)
    if enabled:
        item = listed["items"][0]
        assert item["type"] == ("LIKE" if event == "likes" else "COMMENT")
        assert item["reference_id"] == record_id and item["reference_type"] == "RECORD"
        assert item["is_read"] is False
    assert all(n["type"] == "GROUP_RECORD" for n in call(world, "GET", user=2).json()["items"])


@pytest.mark.parametrize("event", ["likes", "comments"])
def test_self_events_do_not_notify(world, event):
    record_id = create(world).json()["id"]
    response = call(world, "POST", f"/records/{record_id}/{event}",
                    **({"json": {"content": "Own comment"}} if event == "comments" else {}))
    assert response.status_code == (201 if event == "comments" else 200)
    assert call(world, "GET").json()["items"] == []


def test_duplicate_like_does_not_duplicate_notification_and_defaults_allow_events(world):
    record_id = create(world).json()["id"]
    for _ in range(2):
        assert call(world, "POST", f"/records/{record_id}/likes", user=2).status_code == 200
    assert call(world, "GET").json()["total"] == 1
    assert call(world, "DELETE", f"/records/{record_id}/likes", user=2).status_code == 200
    assert call(world, "GET").json()["total"] == 1


def test_failed_and_unauthorized_events_do_not_notify(world):
    record_id = create(world, private=True).json()["id"]
    assert call(world, "POST", f"/records/{record_id}/likes", user=2).status_code == 404
    assert call(world, "POST", f"/records/{record_id}/comments", user=2, json={"content": "Hello"}).status_code == 404
    assert call(world, "POST", f"/records/{record_id}/comments", json={"content": ""}).status_code == 422
    with Session(world[1]) as db:
        assert db.scalar(select(func.count()).select_from(Notification)) == 0


@pytest.mark.parametrize("method,path,payload", [
    ("GET", "/notifications", None), ("GET", "/notifications/unread-count", None),
    ("PATCH", "/notifications/1/read", None), ("PATCH", "/notifications/read-all", None),
    ("GET", "/notifications/settings", None),
    ("PATCH", "/notifications/settings", {"reactions_enabled": False}),
])
@pytest.mark.parametrize("headers", [{}, {"Authorization": "Bearer invalid"}])
def test_authentication_required(world, method, path, payload, headers):
    assert world[0].request(method, path, headers=headers, json=payload).status_code == 401
