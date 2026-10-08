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
import app.records as records_api


class Storage:
    def __init__(self):
        self.objects = {}
        self.deleted = []
        self.fail_at = None

    def upload(self, raw, mime):
        if self.fail_at == len(self.objects):
            raise HTTPException(502, "사진 저장 실패")
        key = f"records/test-{len(self.objects)}.png"
        self.objects[key] = raw
        return UploadedPhoto(key, f"https://storage.example.test/bucket/{key}")

    def delete(self, key):
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
