import io
import json
from datetime import date

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy import create_engine, select, func
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app.db import Base, get_db
from app.db_models import User
from app.main import create_app
from app.object_storage import UploadedPhoto, ObjectStorage
from app.record_models import GroupMember, MemoryGroup, Record, RecordPhoto, RecordGroup
from app.security import hash_password
import app.main as main_api
import app.records as records_api


class Storage:
    def __init__(self):
        self.objects = {}
        self.deleted = []
        self.fail_at = None
        self.fail_delete = False

    def upload(self, raw, mime):
        if self.fail_at == len(self.objects):
            raise HTTPException(502, "사진 저장 실패")
        key = f"records/test-{len(self.objects)}.png"
        self.objects[key] = raw
        return UploadedPhoto(key, f"https://storage.example.test/bucket/{key}")

    def upload_profile(self, user_id, raw, mime):
        if self.fail_at == len(self.objects):
            raise HTTPException(502, "사진 저장 실패")
        key = f"profiles/{user_id}/test-{len(self.objects)}.png"
        self.objects[key] = raw
        return UploadedPhoto(key, f"https://storage.example.test/bucket/{key}")

    def delete(self, key):
        if self.fail_delete:
            raise HTTPException(502, "사진 삭제 실패")
        self.deleted.append(key)
        self.objects.pop(key, None)

    def download(self, key):
        return io.BytesIO(self.objects[key])


@pytest.fixture
def world(monkeypatch):
    # This creates tables only in an isolated, disposable in-memory test DB.
    engine = create_engine("sqlite://", poolclass=StaticPool, connect_args={"check_same_thread": False})
    Base.metadata.create_all(engine)
    with Session(engine) as db:
        for user_id in (1, 2, 3):
            db.add(User(id=user_id, email=f"user{user_id}@test.example", nickname=f"테스트{user_id}",
                        gender="female", birth_date=date(1990, 1, 1), password_hash=hash_password("test-password")))
        db.add_all([MemoryGroup(id=10, name="실제 가입 모임"), MemoryGroup(id=20, name="미가입 모임")])
        db.add_all([GroupMember(group_id=10, user_id=1), GroupMember(group_id=10, user_id=2), GroupMember(group_id=20, user_id=3)])
        db.commit()
    api = create_app(use_db_auth=True)
    def session():
        with Session(engine) as db:
            yield db
    api.dependency_overrides[get_db] = session
    storage = Storage()
    monkeypatch.setattr(records_api, "get_object_storage", lambda: storage)
    monkeypatch.setattr(main_api, "get_object_storage", lambda: storage)
    with TestClient(api) as client:
        headers = {}
        for user_id in (1, 2, 3):
            token = client.post("/auth/login", json={"email": f"user{user_id}@test.example", "password": "test-password"})
            assert token.status_code == 200
            headers[user_id] = {"Authorization": "Bearer " + token.json()["access_token"]}
        yield client, engine, storage, headers
    engine.dispose()


def image():
    buffer = io.BytesIO()
    Image.new("RGB", (2, 2)).save(buffer, format="PNG")
    return buffer.getvalue()


def create(world, user=1, private=False, groups=None, **overrides):
    client, _, _, headers = world
    payload = dict(place=dict(kakao_place_id="123", name="선택한 장소", address="서울", latitude=37.5, longitude=127.0),
                   emotion="good", content="", is_private=private, group_ids=([] if private else [10]) if groups is None else groups)
    payload.update(overrides)
    return client.post("/records", headers=headers[user], data={"data": json.dumps(payload)},
                       files=[("photos", ("photo.png", image(), "image/png"))])


def test_record_save_and_photo_url(world):
    response = create(world)
    assert response.status_code == 201, response.text
    assert response.json()["content"] == ""  # Optional story contract.
    with Session(world[1]) as db:
        record = db.get(Record, response.json()["id"])
        photo = db.scalar(select(RecordPhoto))
        assert record.author_id == 1 and record.emotion == "good"
        assert photo.photo_url == "https://storage.example.test/bucket/records/test-0.png"
        assert photo.object_key == "records/test-0.png"
        assert photo.file_size == len(image())
        assert db.scalar(select(func.count()).select_from(RecordGroup)) == 1
    assert world[0].get(response.json()["photo_urls"][0], headers=world[3][1]).content == image()


def test_author_updates_record_content_emotion_and_scope(world):
    client, engine, _, headers = world
    created = create(world, content="수정 전 내용").json()

    private_update = client.patch(
        f"/records/{created['id']}",
        headers=headers[1],
        json={"content": "수정한 내용", "emotion": "excellent", "is_private": True, "group_ids": []},
    )
    assert private_update.status_code == 200, private_update.text
    assert private_update.json()["content"] == "수정한 내용"
    assert private_update.json()["emotion"] == "excellent"
    assert private_update.json()["is_private"] is True
    assert private_update.json()["shared_groups"] == []

    shared_update = client.patch(
        f"/records/{created['id']}",
        headers=headers[1],
        json={"is_private": False, "group_ids": [10]},
    )
    assert shared_update.status_code == 200, shared_update.text
    assert shared_update.json()["is_private"] is False
    assert [group["id"] for group in shared_update.json()["shared_groups"]] == [10]
    with Session(engine) as db:
        record = db.get(Record, created["id"])
        assert record.content == "수정한 내용"
        assert record.emotion == "excellent"
        assert db.scalars(select(RecordGroup.group_id).where(
            RecordGroup.record_id == created["id"]
        )).all() == [10]
    assert client.get("/feed?mine=true", headers=headers[1]).json()["items"][0]["content"] == "수정한 내용"


def test_record_update_rejects_non_author_invalid_scope_and_nonmember(world):
    client, engine, _, headers = world
    created = create(world, content="원본").json()

    assert client.patch(
        f"/records/{created['id']}", headers=headers[2], json={"content": "다른 사용자 수정"}
    ).status_code == 403
    assert client.patch(
        f"/records/{created['id']}", json={"content": "인증 없음"}
    ).status_code == 401
    assert client.patch(
        f"/records/{created['id']}",
        headers=headers[1],
        json={"is_private": False, "group_ids": [20]},
    ).status_code == 403
    assert client.patch(
        f"/records/{created['id']}",
        headers=headers[1],
        json={"is_private": True, "group_ids": [10]},
    ).status_code == 422
    assert client.patch(
        f"/records/{created['id']}",
        headers=headers[1],
        json={"is_private": False, "group_ids": []},
    ).status_code == 422
    with Session(engine) as db:
        assert db.get(Record, created["id"]).content == "원본"
        assert db.scalars(select(RecordGroup.group_id).where(
            RecordGroup.record_id == created["id"]
        )).all() == [10]


def test_author_deletes_record_relationships_and_exclusive_photo(world):
    client, engine, storage, headers = world
    created = create(world).json()
    with Session(engine) as db:
        object_key = db.scalar(select(RecordPhoto.object_key).where(
            RecordPhoto.record_id == created["id"]
        ))

    deleted = client.delete(f"/records/{created['id']}", headers=headers[1])
    assert deleted.status_code == 204, deleted.text
    assert object_key in storage.deleted
    with Session(engine) as db:
        assert db.get(Record, created["id"]) is None
        assert db.scalars(select(RecordPhoto).where(RecordPhoto.record_id == created["id"])).all() == []
        assert db.scalars(select(RecordGroup).where(RecordGroup.record_id == created["id"])).all() == []
    assert client.get("/feed?mine=true", headers=headers[1]).json()["items"] == []


def test_delete_preserves_object_key_still_referenced_by_another_record(world):
    client, engine, storage, headers = world
    created = create(world).json()
    with Session(engine) as db:
        original = db.get(Record, created["id"])
        original_photo = db.scalar(select(RecordPhoto).where(RecordPhoto.record_id == original.id))
        other = Record(
            author_id=1,
            place_id=original.place_id,
            content="공유 객체를 참조하는 다른 기록",
            emotion="good",
            is_private=True,
        )
        db.add(other)
        db.flush()
        db.add(RecordPhoto(
            record_id=other.id,
            object_key=original_photo.object_key,
            photo_url=original_photo.photo_url,
            original_name=original_photo.original_name,
            mime_type=original_photo.mime_type,
            file_size=original_photo.file_size,
            sort_order=0,
        ))
        db.commit()
        object_key = original_photo.object_key

    assert client.delete(f"/records/{created['id']}", headers=headers[1]).status_code == 204
    assert object_key not in storage.deleted
    assert object_key in storage.objects


def test_storage_delete_failure_never_leaves_the_database_record(world):
    client, engine, storage, headers = world
    created = create(world).json()
    storage.fail_delete = True

    deleted = client.delete(f"/records/{created['id']}", headers=headers[1])
    assert deleted.status_code == 204, deleted.text
    with Session(engine) as db:
        assert db.get(Record, created["id"]) is None
        assert db.scalars(select(RecordPhoto).where(RecordPhoto.record_id == created["id"])).all() == []
    # The private object may remain for a later storage cleanup job, but no API
    # can expose it because its record/photo rows are already gone.
    assert storage.objects


def test_profile_update_persists_partial_changes_and_keeps_authentication(world):
    client, engine, _, headers = world

    nickname_update = client.patch(
        "/auth/me",
        headers=headers[1],
        json={"nickname": "updated-user-one"},
    )
    assert nickname_update.status_code == 200, nickname_update.text
    assert nickname_update.json() == {
        "id": 1,
        "email": "user1@test.example",
        "nickname": "updated-user-one",
        "birth_date": "1990-01-01",
        "gender": "female",
    }

    remaining_update = client.patch(
        "/auth/me",
        headers=headers[1],
        json={"birth_date": "1991-02-03", "gender": "male"},
    )
    assert remaining_update.status_code == 200, remaining_update.text
    assert remaining_update.json()["nickname"] == "updated-user-one"
    assert remaining_update.json()["birth_date"] == "1991-02-03"
    assert remaining_update.json()["gender"] == "male"
    assert client.get("/auth/me", headers=headers[1]).json() == remaining_update.json()

    relogin = client.post(
        "/auth/login",
        json={"email": "user1@test.example", "password": "test-password"},
    )
    assert relogin.status_code == 200, relogin.text
    relogin_headers = {"Authorization": "Bearer " + relogin.json()["access_token"]}
    assert client.get("/auth/me", headers=relogin_headers).json() == remaining_update.json()

    with Session(engine) as db:
        user = db.get(User, 1)
        assert user.nickname == "updated-user-one"
        assert user.birth_date == date(1991, 2, 3)
        assert user.gender == "male"


@pytest.mark.parametrize(
    "payload",
    [
        {},
        {"nickname": "   "},
        {"birth_date": "2999-01-01"},
        {"gender": "other"},
        {"nickname": None},
    ],
)
def test_profile_update_validates_input_without_writing(world, payload):
    client, engine, _, headers = world
    response = client.patch("/auth/me", headers=headers[1], json=payload)
    assert response.status_code == 422

    with Session(engine) as db:
        user = db.get(User, 1)
        assert user.nickname == "테스트1"
        assert user.birth_date == date(1990, 1, 1)
        assert user.gender == "female"


def test_profile_update_only_changes_the_authenticated_user(world):
    client, engine, _, headers = world
    response = client.patch(
        "/auth/me",
        headers=headers[2],
        json={"nickname": "updated-user-two"},
    )
    assert response.status_code == 200, response.text
    assert response.json()["id"] == 2
    assert response.json()["nickname"] == "updated-user-two"

    with Session(engine) as db:
        first_user = db.get(User, 1)
        second_user = db.get(User, 2)
        assert first_user.nickname == "테스트1"
        assert second_user.nickname == "updated-user-two"

    forged_target = client.patch(
        "/auth/me",
        headers=headers[2],
        json={"id": 1, "nickname": "attempted-other-user-update"},
    )
    assert forged_target.status_code == 422
    with Session(engine) as db:
        assert db.get(User, 1).nickname == "테스트1"


def test_profile_photo_upload_get_replace_and_delete(world):
    client, engine, storage, headers = world

    uploaded = client.post(
        "/auth/me/photo",
        headers=headers[1],
        files={"photo": ("profile.png", image(), "image/png")},
    )
    assert uploaded.status_code == 204, uploaded.text
    with Session(engine) as db:
        first_key = db.get(User, 1).profile_image_key
    assert first_key is not None and first_key.startswith("profiles/1/")
    assert first_key in storage.objects

    photo = client.get("/auth/me/photo", headers=headers[1])
    assert photo.status_code == 200
    assert photo.content == image()
    assert photo.headers["cache-control"] == "private, no-store"
    assert client.get("/auth/me/photo", headers=headers[2]).status_code == 404

    replacement = client.post(
        "/auth/me/photo",
        headers=headers[1],
        files={"photo": ("replacement.png", image(), "image/png")},
    )
    assert replacement.status_code == 204, replacement.text
    with Session(engine) as db:
        replacement_key = db.get(User, 1).profile_image_key
    assert replacement_key is not None and replacement_key != first_key
    assert first_key in storage.deleted
    assert first_key not in storage.objects

    other_user_upload = client.post(
        "/auth/me/photo",
        headers=headers[2],
        files={"photo": ("other.png", image(), "image/png")},
    )
    assert other_user_upload.status_code == 204, other_user_upload.text
    with Session(engine) as db:
        assert db.get(User, 1).profile_image_key == replacement_key
        assert db.get(User, 2).profile_image_key.startswith("profiles/2/")

    deleted = client.delete("/auth/me/photo", headers=headers[1])
    assert deleted.status_code == 204, deleted.text
    with Session(engine) as db:
        assert db.get(User, 1).profile_image_key is None
    assert replacement_key in storage.deleted
    assert client.get("/auth/me/photo", headers=headers[1]).status_code == 404


def test_feed_exposes_current_author_photo_through_visible_record(world):
    client, _, storage, headers = world
    record = create(world, user=1).json()
    assert record["author"]["profile_image_url"] is None

    uploaded = client.post(
        "/auth/me/photo",
        headers=headers[1],
        files={"photo": ("profile.png", image(), "image/png")},
    )
    assert uploaded.status_code == 204

    feed = client.get("/feed", headers=headers[2]).json()
    item = next(item for item in feed["items"] if item["id"] == record["id"])
    first_url = item["author"]["profile_image_url"]
    assert first_url.startswith(f"/records/{record['id']}/author-photo?v=")
    photo = client.get(first_url, headers=headers[2])
    assert photo.status_code == 200
    assert photo.content == image()
    assert storage.objects

    replacement = client.post(
        "/auth/me/photo",
        headers=headers[1],
        files={"photo": ("replacement.png", image(), "image/png")},
    )
    assert replacement.status_code == 204
    refreshed_item = next(item for item in client.get("/feed", headers=headers[2]).json()["items"]
                          if item["id"] == record["id"])
    assert refreshed_item["author"]["profile_image_url"] != first_url


def test_profile_photo_requires_authentication_and_valid_image(world):
    client, engine, storage, headers = world
    assert client.post(
        "/auth/me/photo",
        files={"photo": ("profile.png", image(), "image/png")},
    ).status_code == 401
    assert client.get("/auth/me/photo").status_code == 401
    assert client.delete("/auth/me/photo").status_code == 401

    invalid = client.post(
        "/auth/me/photo",
        headers=headers[1],
        files={"photo": ("profile.jpg", b"not-an-image", "image/jpeg")},
    )
    assert invalid.status_code == 422
    too_large = client.post(
        "/auth/me/photo",
        headers=headers[1],
        files={"photo": ("profile.png", b"x" * (5 * 1024 * 1024 + 1), "image/png")},
    )
    assert too_large.status_code == 413
    with Session(engine) as db:
        assert db.get(User, 1).profile_image_key is None

    storage.fail_at = 0
    failed_upload = client.post(
        "/auth/me/photo",
        headers=headers[1],
        files={"photo": ("profile.png", image(), "image/png")},
    )
    assert failed_upload.status_code == 502
    with Session(engine) as db:
        assert db.get(User, 1).profile_image_key is None


def test_group_api_memberships_and_settings_are_shared_with_records(world):
    client, engine, _, headers = world
    response = client.post("/groups", headers=headers[1], json={
        "name": "통합 모임", "description": "모임과 기록 연동",
        "visibility": "INVITED_ONLY",
    })
    assert response.status_code == 201, response.text
    group = response.json()
    group_id = group["id"]
    invite = client.get(f"/groups/{group_id}/invite", headers=headers[1])
    assert invite.status_code == 200
    assert invite.json()["invite_code"] == group["invite_code"]
    joined = client.post("/groups/join", headers=headers[2], json={
        "invite_code": group["invite_code"],
    })
    assert joined.status_code == 200, joined.text
    assert joined.json()["member_count"] == 2
    preferences = client.patch(f"/groups/{group_id}/preferences", headers=headers[2], json={
        "custom_name": "내 별칭", "notifications_enabled": False,
        "pin_color_value": 0xFF6FAE8F,
    })
    assert preferences.status_code == 200, preferences.text
    assert preferences.json()["display_name"] == "내 별칭"
    with Session(engine) as db:
        member = db.get(GroupMember, (group_id, 2))
        assert member.custom_name == "내 별칭"
        assert member.notifications_enabled is False
        assert db.get(MemoryGroup, group_id).name == "통합 모임"
    record_groups = client.get("/records/groups", headers=headers[2])
    assert record_groups.status_code == 200
    assert any(item["id"] == group_id for item in record_groups.json())
    saved = create(world, groups=[group_id])
    assert saved.status_code == 201, saved.text
    record = saved.json()
    assert record["id"] in feed_ids(world, 2, f"?group_id={group_id}")
    assert client.get(record["photo_urls"][0], headers=headers[2]).status_code == 200
    assert client.delete(f"/groups/{group_id}/members/me", headers=headers[2]).status_code == 204
    assert record["id"] not in feed_ids(world, 2)
    assert client.get(record["photo_urls"][0], headers=headers[2]).status_code == 404


def test_personalized_feed_and_private_visibility(world):
    own = create(world, private=True).json()
    shared = create(world, user=2).json()
    other_private = create(world, user=2, private=True).json()
    stranger = create(world, user=3, groups=[20]).json()
    client, _, _, headers = world
    records = client.get("/feed", headers=headers[1]).json()
    assert records["total"] == 2
    assert {r["id"] for r in records["items"]} == {own["id"], shared["id"]}
    assert client.get("/feed?mine=true", headers=headers[1]).json()["items"][0]["id"] == own["id"]
    assert {r["id"] for r in client.get("/feed?group_id=10", headers=headers[1]).json()["items"]} == {shared["id"]}
    for record in [other_private, stranger]:
        assert client.get(record["photo_urls"][0], headers=headers[1]).status_code == 404
    assert client.get(own["photo_urls"][0], headers=headers[2]).status_code == 404
    assert client.get("/feed?group_id=20", headers=headers[1]).status_code == 403
    assert client.get("/feed").status_code == 401


def test_feed_filters_by_place_without_bypassing_visibility(world):
    own_at_target = create(world, private=True).json()
    shared_at_target = create(world, user=2).json()
    visible_elsewhere = create(
        world,
        user=2,
        place=dict(
            kakao_place_id="456",
            name="다른 장소",
            address="서울",
            latitude=37.6,
            longitude=127.1,
        ),
    ).json()
    hidden_private_at_target = create(world, user=2, private=True).json()
    hidden_nonmember_at_target = create(world, user=3, groups=[20]).json()
    client, _, _, headers = world
    target_id = own_at_target["place"]["id"]

    filtered = client.get(f"/feed?place_id={target_id}", headers=headers[1])
    assert filtered.status_code == 200
    assert filtered.json()["total"] == 2
    assert {item["id"] for item in filtered.json()["items"]} == {
        own_at_target["id"],
        shared_at_target["id"],
    }
    assert visible_elsewhere["id"] not in {
        item["id"] for item in filtered.json()["items"]
    }
    assert hidden_private_at_target["id"] not in {
        item["id"] for item in filtered.json()["items"]
    }
    assert hidden_nonmember_at_target["id"] not in {
        item["id"] for item in filtered.json()["items"]
    }

    assert {
        item["id"]
        for item in client.get(
            f"/feed?place_id={target_id}&mine=true", headers=headers[1]
        ).json()["items"]
    } == {own_at_target["id"]}
    assert {
        item["id"]
        for item in client.get(
            f"/feed?place_id={target_id}&group_id=10", headers=headers[1]
        ).json()["items"]
    } == {shared_at_target["id"]}
    assert client.get("/feed?place_id=999999", headers=headers[1]).json() == {
        "items": [],
        "total": 0,
        "offset": 0,
        "limit": 20,
    }
    assert {
        item["id"] for item in client.get("/feed", headers=headers[1]).json()["items"]
    } == {own_at_target["id"], shared_at_target["id"], visible_elsewhere["id"]}


def feed_ids(world, user, query=""):
    response = world[0].get("/feed" + query, headers=world[3][user])
    assert response.status_code == 200
    return {record["id"] for record in response.json()["items"]}


def test_author_sees_own_personal_record(world):
    record = create(world, user=1, private=True).json()
    assert feed_ids(world, 1) == {record["id"]}


def test_other_user_cannot_see_personal_record(world):
    create(world, user=1, private=True)
    assert feed_ids(world, 2) == set()


def test_private_record_visible_only_to_author_even_with_legacy_group_link(world):
    record = create(world, user=1, private=True).json()
    # An inconsistent legacy association must never override private visibility.
    with Session(world[1]) as db:
        db.add(RecordGroup(record_id=record["id"], group_id=10))
        db.commit()
    assert feed_ids(world, 1) == {record["id"]}
    assert feed_ids(world, 2) == set()
    assert feed_ids(world, 3) == set()


def test_joined_group_member_sees_shared_record(world):
    record = create(world, user=1).json()
    assert feed_ids(world, 2) == {record["id"]}


def test_nonmember_cannot_see_shared_record(world):
    create(world, user=1)
    assert feed_ids(world, 3) == set()


def test_author_loses_shared_record_access_after_leaving_group(world):
    record = create(world).json()
    client, _, _, headers = world
    assert client.delete("/groups/10/members/me", headers=headers[1]).status_code == 204
    assert feed_ids(world, 1) == set()
    assert client.get(record["photo_urls"][0], headers=headers[1]).status_code == 404
    assert client.get("/map/places", headers=headers[1]).json() == []
    assert feed_ids(world, 2) == {record["id"]}


def test_invite_generation_validation_join_and_duplicate_prevention(world):
    client, engine, _, headers = world
    created = client.post("/groups", headers=headers[1], json={"name": "Invitation test"})
    assert created.status_code == 201
    group = created.json()
    code = group["invite_code"]
    assert len(code) == 12 and code.isalnum() and code == code.upper()
    assert client.get(f"/groups/{group['id']}/invite", headers=headers[3]).status_code == 404
    payload = {"invite_code": " " + code.lower() + " "}
    preview = client.post("/groups/invite/validate?user_id=1", headers=headers[3], json=payload)
    assert preview.status_code == 200
    assert preview.json()["id"] == group["id"]
    with Session(engine) as db:
        assert db.get(GroupMember, (group["id"], 3)) is None
    joined = client.post("/groups/join?user_id=1", headers=headers[3], json=payload)
    assert joined.status_code == 200
    assert joined.json()["member_count"] == 2
    assert client.post("/groups/join", headers=headers[3], json=payload).status_code == 409
    with Session(engine) as db:
        assert db.get(GroupMember, (group["id"], 3)) is not None
        assert db.scalar(select(func.count()).select_from(GroupMember).where(
            GroupMember.group_id == group["id"])) == 2


@pytest.mark.parametrize("path", ["/groups/invite/validate", "/groups/join"])
def test_invalid_disabled_and_unauthenticated_invites(world, path):
    client, engine, _, headers = world
    assert client.post(path, headers=headers[3], json={"invite_code": "INVALIDCODE123"}).status_code == 404
    created = client.post("/groups", headers=headers[1], json={"name": "Disabled invitation"}).json()
    payload = {"invite_code": created["invite_code"]}
    assert client.post(path, json=payload).status_code == 401
    assert client.post(path, headers={"Authorization": "Bearer invalid"}, json=payload).status_code == 401
    with Session(engine) as db:
        db.get(MemoryGroup, created["id"]).invite_enabled = False
        db.commit()
    assert client.post(path, headers=headers[3], json=payload).status_code == 403
    assert client.get(f"/groups/{created['id']}/invite", headers=headers[1]).status_code == 403
    with Session(engine) as db:
        assert db.get(GroupMember, (created["id"], 3)) is None


def test_unshared_nonprivate_record_is_not_public(world):
    record = create(world, user=1).json()
    with Session(world[1]) as db:
        db.delete(db.get(RecordGroup, (record["id"], 10)))
        db.commit()
    assert feed_ids(world, 1) == set()
    assert feed_ids(world, 2) == set()


def test_client_user_id_cannot_override_authenticated_identity(world):
    own = create(world, user=1, private=True).json()
    create(world, user=2, private=True)
    assert feed_ids(world, 1, "?user_id=2") == {own["id"]}
    assert feed_ids(world, 2, "?user_id=1&mine=true") != {own["id"]}
    assert world[0].get("/feed?user_id=1").status_code == 401


def test_multiple_joined_groups_do_not_duplicate_records_or_total(world):
    with Session(world[1]) as db:
        db.add_all([GroupMember(group_id=20, user_id=1), GroupMember(group_id=20, user_id=2)])
        db.commit()
    first = create(world, user=1, groups=[10, 20]).json()
    second = create(world, user=1, groups=[10, 20]).json()
    pages = [world[0].get(f"/feed?limit=1&offset={offset}", headers=world[3][2]).json()
             for offset in (0, 1, 2)]
    assert all(page["total"] == 2 for page in pages)
    assert [row["id"] for page in pages for row in page["items"]] == [second["id"], first["id"]]


def test_no_fake_groups_or_posts_and_membership_revocation(world):
    client, engine, _, headers = world
    assert client.get("/feed", headers=headers[1]).json()["items"] == []
    assert [g["name"] for g in client.get("/records/groups", headers=headers[1]).json()] == ["실제 가입 모임"]
    record = create(world, user=2).json()
    with Session(engine) as db:
        db.delete(db.get(GroupMember, (10, 1)))
        db.commit()
    assert client.get("/records/groups", headers=headers[1]).json() == []
    assert client.get("/feed", headers=headers[1]).json()["items"] == []
    assert client.get(record["photo_urls"][0], headers=headers[1]).status_code == 404


@pytest.mark.parametrize("changes,status", [
    ({"groups": [20]}, 403), ({"private": True, "groups": [10]}, 422),
    ({"groups": []}, 422), ({"emotion": "fake"}, 422), ({"content": "a" * 301}, 422),
    ({"place": {"kakao_place_id": "fake"}}, 422),
])
def test_invalid_record_does_not_upload(world, changes, status):
    assert create(world, **changes).status_code == status
    assert world[2].objects == {}


def test_invalid_and_missing_photos(world):
    client, _, _, headers = world
    data = json.dumps(dict(place=dict(kakao_place_id="1", name="장소", address="서울", latitude=37, longitude=127),
                           emotion="good", is_private=True))
    assert client.post("/records", headers=headers[1], data={"data": data}).status_code == 422
    assert client.post("/records", headers=headers[1], data={"data": data},
                       files=[("photos", ("fake.png", b"not an image", "image/png"))]).status_code == 422
    assert not world[2].objects


def test_failed_upload_rolls_back_record(world):
    world[2].fail_at = 0
    assert create(world).status_code == 502
    with Session(world[1]) as db:
        assert db.scalar(select(func.count()).select_from(Record)) == 0
        assert db.scalar(select(func.count()).select_from(RecordPhoto)) == 0


def test_missing_ncp_settings_are_names_only(monkeypatch):
    import app.object_storage as module
    monkeypatch.setattr(module, "dotenv_values", lambda _: {})
    with pytest.raises(HTTPException) as error:
        ObjectStorage()
    assert error.value.status_code == 503
    assert "NCP_ACCESS_KEY" in error.value.detail


def test_partial_upload_failure_cleans_storage_and_database(world):
    client, engine, storage, headers = world
    storage.fail_at = 1
    payload = dict(place=dict(kakao_place_id="123", name="장소", address="서울", latitude=37, longitude=127),
                   emotion="good", is_private=True)
    response = client.post("/records", headers=headers[1], data={"data": json.dumps(payload)},
                           files=[("photos", ("one.png", image(), "image/png")),
                                  ("photos", ("two.png", image(), "image/png"))])
    assert response.status_code == 502
    assert storage.objects == {}
    assert storage.deleted == ["records/test-0.png"]
    with Session(engine) as db:
        assert db.scalar(select(func.count()).select_from(Record)) == 0
        assert db.scalar(select(func.count()).select_from(RecordPhoto)) == 0
