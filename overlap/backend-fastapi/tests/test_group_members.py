from sqlalchemy.orm import Session

from app.db_models import User
from test_records import world


def test_group_members_returns_only_joined_users_and_safe_fields(world):
    client, engine, _, headers = world

    response = client.get("/groups/10/members", headers=headers[1])

    assert response.status_code == 200, response.text
    payload = response.json()
    for member in payload:
        member.pop("profile_image_url", None)
    assert payload == [
        {"id": 1, "nickname": "테스트1", "is_current_user": True},
        {"id": 2, "nickname": "테스트2", "is_current_user": False},
    ]
    assert all(
        set(member) == {"id", "nickname", "is_current_user", "profile_image_url"}
        for member in response.json()
    )
    assert client.get("/groups/10/members").status_code == 401
    # User 3 belongs to a different group and must not discover group 10.
    assert client.get("/groups/10/members", headers=headers[3]).status_code == 404

    with Session(engine) as db:
        db.get(User, 2).nickname = None
        db.commit()

    fallback = client.get("/groups/10/members", headers=headers[1])
    assert fallback.status_code == 200
    assert fallback.json()[1]["nickname"] == "사용자 2"


def test_group_member_profile_photo_is_scoped_and_served(world):
    client, engine, storage, headers = world
    with Session(engine) as db:
        db.get(User, 2).profile_image_key = "profiles/2/avatar.png"
        db.commit()
    storage.objects["profiles/2/avatar.png"] = b"member-photo"

    members = client.get("/groups/10/members", headers=headers[1])
    assert members.status_code == 200
    assert members.json()[1]["profile_image_url"] == "/groups/10/members/2/photo"

    photo = client.get("/groups/10/members/2/photo", headers=headers[1])
    assert photo.status_code == 200
    assert photo.content == b"member-photo"
    assert client.get("/groups/10/members/2/photo", headers=headers[3]).status_code == 404


def test_group_members_reflect_join_and_leave_without_duplicate_rows(world):
    client, _, _, headers = world
    created = client.post(
        "/groups",
        headers=headers[1],
        json={"name": "멤버 갱신 모임"},
    )
    assert created.status_code == 201, created.text
    group_id = created.json()["id"]

    initial = client.get(f"/groups/{group_id}/members", headers=headers[1])
    assert initial.status_code == 200
    initial_payload = initial.json()
    for member in initial_payload:
        member.pop("profile_image_url", None)
    assert initial_payload == [
        {"id": 1, "nickname": "테스트1", "is_current_user": True},
    ]

    joined = client.post(
        "/groups/join",
        headers=headers[2],
        json={"invite_code": created.json()["invite_code"]},
    )
    assert joined.status_code == 200, joined.text

    after_join = client.get(f"/groups/{group_id}/members", headers=headers[1])
    assert after_join.status_code == 200
    assert [member["id"] for member in after_join.json()] == [1, 2]
    assert len({member["id"] for member in after_join.json()}) == 2

    left = client.delete(
        f"/groups/{group_id}/members/me",
        headers=headers[2],
    )
    assert left.status_code == 204

    after_leave = client.get(f"/groups/{group_id}/members", headers=headers[1])
    assert after_leave.status_code == 200
    assert [member["id"] for member in after_leave.json()] == [1]
