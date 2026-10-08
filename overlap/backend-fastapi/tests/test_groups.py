from fastapi.testclient import TestClient
from fastapi import HTTPException

from app import group_management_service, group_service
from app.db import get_db
from app.group_db_models import GroupMember, MemoryGroup
from app.main import create_app
from app.models import (
    GroupCreated,
    GroupPreferencesInput,
    GroupPublic,
    GroupUpdateInput,
)
from app.service import MemoryService


def _account(client: TestClient, email: str) -> dict[str, str]:
    password = "test-password-123!"
    registered = client.post(
        "/auth/register",
        json={
            "email": email,
            "password": password,
            "nickname": "tester",
            "birth_date": "1995-05-17",
            "gender": "female",
            "terms_accepted": True,
        },
    )
    assert registered.status_code == 201
    response = client.post(
        "/auth/login",
        json={"email": email, "password": password},
    )
    assert response.status_code == 200
    return {"Authorization": f"Bearer {response.json()['access_token']}"}


def test_group_routes_keep_memory_test_mode_compatible():
    with TestClient(create_app(MemoryService())) as client:
        owner = _account(client, "owner@example.com")
        member = _account(client, "member@example.com")

        created = client.post(
            "/groups",
            headers=owner,
            json={"name": "테스트 모임"},
        )
        assert created.status_code == 201
        payload = created.json()
        assert payload["name"] == "테스트 모임"
        assert payload["member_count"] == 1
        assert "owner_id" not in payload

        invite = client.get(
            f"/groups/{payload['id']}/invite",
            headers=owner,
        )
        assert invite.status_code == 200
        assert invite.json()["invite_code"] == payload["invite_code"]

        joined = client.post(
            "/groups/join",
            headers=member,
            json={"invite_code": payload["invite_code"]},
        )
        assert joined.status_code == 200
        assert joined.json()["member_count"] == 2

        listed = client.get("/groups", headers=member)
        assert listed.status_code == 200
        assert [group["name"] for group in listed.json()] == ["테스트 모임"]
        assert listed.json()[0]["member_count"] == 2


def test_group_routes_require_authentication():
    with TestClient(create_app(MemoryService())) as client:
        assert client.get("/groups").status_code == 401
        assert client.post("/groups", json={"name": "테스트 모임"}).status_code == 401


def test_group_routes_use_database_service_when_session_is_available(monkeypatch):
    app = create_app(MemoryService())
    session = object()
    app.dependency_overrides[get_db] = lambda: session
    monkeypatch.setattr(
        group_management_service,
        "create_group",
        lambda db, *, user_id, name, description, visibility: GroupCreated(
            id=41,
            name=name,
            member_count=1,
            invite_code="DBGROUPCODE1",
        ),
    )
    monkeypatch.setattr(
        group_service,
        "join_group",
        lambda db, *, user_id, invite_code: GroupPublic(
            id=41,
            name="테스트 모임",
            member_count=2,
        ),
    )
    monkeypatch.setattr(
        group_service,
        "list_groups",
        lambda db, *, user_id: [
            GroupPublic(id=41, name="테스트 모임", member_count=2),
        ],
    )
    monkeypatch.setattr(
        group_service,
        "get_invite",
        lambda db, *, user_id, group_id: "DBGROUPCODE1",
    )

    with TestClient(app) as client:
        headers = _account(client, "database-route@example.com")
        created = client.post(
            "/groups",
            headers=headers,
            json={"name": "테스트 모임"},
        )
        assert created.status_code == 201
        assert created.json()["invite_code"] == "DBGROUPCODE1"
        assert client.get("/groups", headers=headers).json()[0]["id"] == 41
        assert client.get("/groups/41/invite", headers=headers).json() == {
            "invite_code": "DBGROUPCODE1",
        }
        joined = client.post(
            "/groups/join",
            headers=headers,
            json={"invite_code": "DBGROUPCODE1"},
        )
        assert joined.status_code == 200
        assert joined.json()["member_count"] == 2


def test_group_management_routes_delegate_authenticated_requests(monkeypatch):
    app = create_app(MemoryService())
    session = object()
    app.dependency_overrides[get_db] = lambda: session
    monkeypatch.setattr(
        group_management_service,
        "update_group",
        lambda db, *, user_id, group_id, data: GroupPublic(
            id=group_id,
            name="원본 공용 이름",
            display_name="내 별칭",
            member_count=2,
            description=data.description,
            visibility=data.visibility,
        ),
    )
    monkeypatch.setattr(
        group_management_service,
        "update_preferences",
        lambda db, *, user_id, group_id, data: GroupPublic(
            id=group_id,
            name="test group",
            display_name=data.custom_name or "test group",
            member_count=2,
            notifications_enabled=data.notifications_enabled,
            pin_color_value=data.pin_color_value,
        ),
    )
    monkeypatch.setattr(group_management_service, "leave_group", lambda *args, **kwargs: None)

    with TestClient(app) as client:
        headers = _account(client, "group-settings@example.com")
        changed = client.put(
            "/groups/41",
            headers=headers,
            json={"description": "description", "visibility": "LINK_REQUEST_ALLOWED"},
        )
        assert changed.status_code == 200
        assert changed.json()["description"] == "description"
        assert changed.json()["visibility"] == "LINK_REQUEST_ALLOWED"
        rejected_shared_rename = client.put(
            "/groups/41",
            headers=headers,
            json={"name": "공용 이름 변경 금지", "description": "description", "visibility": "INVITED_ONLY"},
        )
        assert rejected_shared_rename.status_code == 422
        prefs = client.patch(
            "/groups/41/preferences",
            headers=headers,
            json={"custom_name": "가족방", "notifications_enabled": False, "pin_color_value": 4285552744},
        )
        assert prefs.status_code == 200
        assert prefs.json()["notifications_enabled"] is False
        assert prefs.json()["display_name"] == "가족방"
        assert client.delete("/groups/41/members/me", headers=headers).status_code == 204


class _FakeGroupSession:
    def __init__(self):
        self.group = MemoryGroup(
            id=10,
            name="모임",
            description=None,
            visibility="INVITED_ONLY",
            invite_code="GROUPCODE123",
            invite_enabled=True,
        )
        self.members = {
            (10, 1): GroupMember(
                group_id=10, user_id=1, custom_name=None,
                notifications_enabled=True, pin_color_value=0xFFFF0000,
            ),
            (10, 2): GroupMember(
                group_id=10, user_id=2, custom_name=None,
                notifications_enabled=True, pin_color_value=0xFF0000FF,
            ),
        }

    def get(self, model, key):
        if model is GroupMember:
            return self.members.get((key["group_id"], key["user_id"]))
        if model is MemoryGroup:
            return self.group if key == 10 else None
        return None

    def scalar(self, statement):
        if statement.column_descriptions[0].get("entity") is MemoryGroup:
            return self.group
        return len([key for key in self.members if key[0] == 10])

    def scalars(self, statement):
        params = statement.compile().params
        return [member.user_id for member in self.members.values()
                if member.group_id in params["group_id_1"]
                and member.user_id != params["user_id_1"]
                and member.notifications_enabled]

    def add(self, instance):
        if not hasattr(self, "notifications"):
            self.notifications = []
        self.notifications.append(instance)

    def flush(self):
        pass

    def rollback(self):
        pass

    def commit(self):
        pass

    def refresh(self, _instance):
        pass


def test_preferences_are_per_member_and_display_name_falls_back_to_group_name():
    db = _FakeGroupSession()
    response_a = group_management_service.update_preferences(
        db,
        user_id=1,
        group_id=10,
        data=GroupPreferencesInput(
            custom_name="가족방",
            pin_color_value=0xFFFF6B6B,
            notifications_enabled=False,
        ),
    )
    response_b = group_service._to_group_public(db, db.group, user_id=2)

    assert response_a.name == "모임"
    assert response_a.display_name == "가족방"
    assert response_a.pin_color_value == 0xFFFF6B6B
    assert response_a.notifications_enabled is False
    assert response_b.name == "모임"
    assert response_b.display_name == "모임"
    assert response_b.pin_color_value == 0xFF0000FF
    assert response_b.notifications_enabled is True


def test_clearing_custom_name_restores_shared_name_and_shared_update_does_not_rename_group():
    db = _FakeGroupSession()
    group_management_service.update_preferences(
        db, user_id=1, group_id=10,
        data=GroupPreferencesInput(custom_name="가족방"),
    )
    group_management_service.update_preferences(
        db, user_id=1, group_id=10,
        data=GroupPreferencesInput(custom_name=None),
    )
    group_management_service.update_group(
        db, user_id=1, group_id=10,
        data=GroupUpdateInput(description="소개", visibility="LINK_REQUEST_ALLOWED"),
    )

    assert db.group.name == "모임"
    assert group_service._to_group_public(db, db.group, user_id=1).display_name == "모임"


def test_non_member_cannot_update_group_preferences():
    db = _FakeGroupSession()
    try:
        group_management_service.update_preferences(
            db, user_id=99, group_id=10,
            data=GroupPreferencesInput(custom_name="별칭"),
        )
    except HTTPException as error:
        assert error.status_code == 404
    else:
        raise AssertionError("non-members must not update group preferences")


def test_invite_code_joins_directly_even_when_visibility_allows_link_access(monkeypatch):
    db = _FakeGroupSession()
    db.group.visibility = "LINK_REQUEST_ALLOWED"
    added_members = []

    monkeypatch.setattr(
        group_service.group_repository,
        "get_group_by_invite_code",
        lambda session, code: db.group if code == "GROUPCODE123" else None,
    )
    monkeypatch.setattr(group_service.group_repository, "is_member", lambda *args, **kwargs: False)

    def add_member(session, *, group_id, user_id):
        added_members.append((group_id, user_id))
        session.members[(group_id, user_id)] = GroupMember(
            group_id=group_id,
            user_id=user_id,
            custom_name=None,
            notifications_enabled=True,
            pin_color_value=None,
        )

    monkeypatch.setattr(group_service.group_repository, "add_member", add_member)

    joined = group_service.join_group(db, user_id=3, invite_code="groupcode123")

    assert added_members == [(10, 3)]
    assert joined.id == 10
    assert joined.display_name == "모임"
