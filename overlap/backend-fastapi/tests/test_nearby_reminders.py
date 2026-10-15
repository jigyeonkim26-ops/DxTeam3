from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.notification_models import Notification, NotificationSettings
from test_records import create, world


def call(world, payload, user=1):
    return world[0].post(
        "/reminders/nearby", headers=world[3][user], json=payload
    )


def reminder_rows(world, user_id=1):
    with Session(world[1]) as db:
        return db.scalars(
            select(Notification)
            .where(
                Notification.user_id == user_id,
                Notification.type == "NEARBY_REMINDER",
            )
            .order_by(Notification.id)
        ).all()


def test_nearby_reminders_create_record_notifications_and_return_detail(world):
    created = create(world).json()

    response = call(world, {"latitude": 37.5, "longitude": 127.0})

    assert response.status_code == 200, response.text
    item = response.json()["items"][0]
    assert item["record"]["id"] == created["id"]
    assert item["distance_meters"] == 0
    assert item["notification_created"] is True
    rows = reminder_rows(world)
    assert len(rows) == 1
    assert rows[0].reference_type == "RECORD"
    assert rows[0].reference_id == created["id"]
    assert rows[0].is_read is False
    assert world[0].get(
        "/notifications/unread-count", headers=world[3][1]
    ).json()["unread_count"] == 1


def test_reminder_is_deduplicated_for_24_hours_then_created_again(world):
    created = create(world).json()
    payload = {"latitude": 37.5, "longitude": 127.0}

    first = call(world, payload).json()["items"][0]
    second = call(world, payload).json()["items"][0]
    assert first["notification_created"] is True
    assert second["notification_created"] is False
    assert second["notification_id"] == first["notification_id"]
    assert len(reminder_rows(world)) == 1

    with Session(world[1]) as db:
        reminder = db.get(Notification, first["notification_id"])
        reminder.created_at = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(
            hours=24, seconds=1
        )
        db.commit()

    after_window = call(world, payload).json()["items"][0]
    assert after_window["notification_created"] is True
    assert after_window["notification_id"] != first["notification_id"]
    assert len(reminder_rows(world)) == 2
    assert created["id"] == after_window["record"]["id"]


def test_reminder_uses_only_the_authenticated_users_own_records(world):
    create(
        world,
        place={
            "kakao_place_id": "123",
            "name": "내 먼 장소",
            "address": "서울",
            "latitude": 35.0,
            "longitude": 126.0,
        },
    )
    other = create(
        world,
        user=2,
        place={
            "kakao_place_id": "456",
            "name": "다른 사용자 장소",
            "address": "서울",
            "latitude": 37.5,
            "longitude": 127.0,
        },
    )
    assert other.status_code == 201

    response = call(world, {"latitude": 37.5, "longitude": 127.0})
    assert response.status_code == 200
    assert response.json() == {"items": []}
    assert reminder_rows(world) == []


def test_reminder_respects_setting_and_validates_location(world):
    create(world)
    with Session(world[1]) as db:
        db.add(NotificationSettings(user_id=1, nearby_reminder_enabled=False))
        db.commit()

    assert call(world, {"latitude": 37.5, "longitude": 127.0}).json() == {
        "items": []
    }
    assert reminder_rows(world) == []
    assert call(world, {"latitude": 91, "longitude": 127}).status_code == 422
    assert world[0].post(
        "/reminders/nearby", json={"latitude": 37.5, "longitude": 127}
    ).status_code == 401
