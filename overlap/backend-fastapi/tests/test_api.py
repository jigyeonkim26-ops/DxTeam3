from concurrent.futures import ThreadPoolExecutor
from datetime import timedelta

import pytest
from fastapi.testclient import TestClient

from app.main import create_app
from app.models import today_in_korea
from app.security import token_digest
from app.service import MemoryService, now_utc

PASSWORD = "overlap-demo-123!"


def account(client, username):
    result = client.post("/auth/register", json={
        "username": username, "display_name": username, "password": PASSWORD,
    })
    assert result.status_code == 201, result.text
    token = client.post("/auth/login", json={"username": username, "password": PASSWORD})
    assert token.status_code == 200, token.text
    return result.json(), {"Authorization": "Bearer " + token.json()["access_token"]}


@pytest.fixture
def world():
    service = MemoryService()
    with TestClient(create_app(service)) as client:
        alice, a = account(client, "alice")
        bob, b = account(client, "bob")
        carol, c = account(client, "carol")
        group_result = client.post("/groups", headers=a, json={"name": "대학교 친구"})
        assert group_result.status_code == 201
        group = group_result.json()
        joined = client.post("/groups/join", headers=b, json={"invite_code": group["invite_code"]})
        assert joined.status_code == 200
        place_result = client.post(f"/groups/{group['id']}/places", headers=a, json={
            "name": "오버랩 테스트 장소", "address": "테스트용 주소", "latitude": 36.35, "longitude": 127.38,
        })
        assert place_result.status_code == 201
        yield {"client": client, "service": service, "a": a, "b": b, "c": c,
               "alice": alice, "bob": bob, "carol": carol, "group": group, "place": place_result.json()}


def add_memory(world, headers=None, visited_on="2024-05-01", content="같은 장소에 남긴 추억"):
    response = world["client"].post(f"/groups/{world['group']['id']}/memories", headers=headers or world["a"],
                                    json={"place_id": world["place"]["id"], "content": content,
                                          "visited_on": visited_on})
    assert response.status_code == 201, response.text
    return response.json()


def test_health_docs_and_openapi():
    with TestClient(create_app()) as client:
        assert client.get("/health").json() == {"status": "ok", "storage": "memory"}
        assert client.get("/docs").status_code == 200
        schema = client.get("/openapi.json").json()
        assert schema["paths"]["/groups"]["post"]["security"] == [{"HTTPBearer": []}]
        assert len(schema["paths"]) >= 10


def test_auth_hashing_duplicate_login_and_logout(world):
    client, service = world["client"], world["service"]
    assert client.get("/groups").status_code == 401
    assert client.get("/groups", headers={"Authorization": "Bearer forged"}).status_code == 401
    assert client.get("/auth/me", headers=world["a"]).json() == world["alice"]
    stored = service.users[world["alice"]["id"]].password_hash
    assert stored.startswith("$argon2id$") and PASSWORD not in stored
    duplicate = client.post("/auth/register", json={"username": "ALICE", "display_name": "다른 이름", "password": PASSWORD})
    assert duplicate.status_code == 409
    for username in ["alice", "missing_user"]:
        failure = client.post("/auth/login", json={"username": username, "password": "wrong"})
        assert failure.status_code == 401
        assert failure.json()["detail"] == "아이디 또는 비밀번호가 올바르지 않습니다."
    assert client.post("/auth/logout", headers=world["a"]).status_code == 204
    assert client.get("/auth/me", headers=world["a"]).status_code == 401


def test_expired_session_is_rejected(world):
    raw_token = world["a"]["Authorization"].split(" ", 1)[1]
    world["service"].sessions[token_digest(raw_token)].expires_at = now_utc() - timedelta(seconds=1)
    assert world["client"].get("/groups", headers=world["a"]).status_code == 401


def test_validation_does_not_echo_password():
    with TestClient(create_app()) as client:
        response = client.post("/auth/register", json={"username": "hi", "display_name": "이름", "password": "secret"})
        assert response.status_code == 422
        assert "secret" not in response.text
        assert all("input" not in error for error in response.json()["detail"])


def test_invites_and_duplicate_membership(world):
    client, group_id = world["client"], world["group"]["id"]
    assert client.get("/groups", headers=world["c"]).json() == []
    assert client.get(f"/groups/{group_id}/invite", headers=world["b"]).status_code == 403
    owner_invite = client.get(f"/groups/{group_id}/invite", headers=world["a"]).json()
    assert owner_invite["invite_code"] == world["group"]["invite_code"]
    for _ in range(2):
        result = client.post("/groups/join", headers=world["b"], json=owner_invite)
        assert result.json()["member_count"] == 2
    public_groups = client.get("/groups", headers=world["b"]).json()
    assert "invite_code" not in public_groups[0]
    assert client.post("/groups/join", headers=world["c"], json={"invite_code": "invalid-invite-code"}).status_code == 404


def test_nonmember_cannot_read_or_write_any_group_data(world):
    client, gid, pid = world["client"], world["group"]["id"], world["place"]["id"]
    memory = add_memory(world)
    for path in [f"/groups/{gid}/places", f"/groups/{gid}/memories", f"/groups/{gid}/map",
                 f"/groups/{gid}/memories/{memory['id']}", f"/groups/{gid}/places/{pid}/timeline", f"/groups/{gid}/invite"]:
        assert client.get(path, headers=world["c"]).status_code == 404, path
    payload = {"place_id": pid, "content": "허용되지 않은 기록", "visited_on": "2024-01-01"}
    assert client.post(f"/groups/{gid}/memories", headers=world["c"], json=payload).status_code == 404
    assert client.put(f"/groups/{gid}/memories/{memory['id']}", headers=world["c"], json=payload).status_code == 404
    assert client.delete(f"/groups/{gid}/memories/{memory['id']}", headers=world["c"]).status_code == 404
    assert client.post(f"/groups/{gid}/places", headers=world["c"], json={
        "name": "장소", "address": "주소", "latitude": 36, "longitude": 127,
    }).status_code == 404


def test_overlap_timeline_uses_visit_date_and_map_groups_by_place(world):
    client, gid, pid = world["client"], world["group"]["id"], world["place"]["id"]
    newer = add_memory(world, visited_on="2025-04-01", content="나의 기억")
    older = add_memory(world, headers=world["b"], visited_on="2023-06-01", content="친구의 이전 기억")
    timeline = client.get(f"/groups/{gid}/places/{pid}/timeline", headers=world["a"]).json()
    assert [item["id"] for item in timeline["items"]] == [older["id"], newer["id"]]
    assert older["created_at"][:10] != older["visited_on"]
    assert {item["author"]["id"] for item in timeline["items"]} == {world["alice"]["id"], world["bob"]["id"]}
    pins = client.get(f"/groups/{gid}/map", headers=world["b"]).json()
    assert pins["total"] == 1
    assert pins["items"][0]["memory_count"] == 2
    assert pins["items"][0]["contributor_count"] == 2
    assert pins["items"][0]["first_visited_on"] == "2023-06-01"
    assert pins["items"][0]["last_visited_on"] == "2025-04-01"


def test_only_author_can_modify_or_delete_and_map_counts_update(world):
    client, gid = world["client"], world["group"]["id"]
    memory = add_memory(world, headers=world["b"])
    path = f"/groups/{gid}/memories/{memory['id']}"
    payload = {"place_id": world["place"]["id"], "content": "수정한 기억", "visited_on": "2024-06-01"}
    # 모임장이라도 다른 사람의 글은 수정/삭제할 수 없습니다.
    assert client.put(path, headers=world["a"], json=payload).status_code == 403
    assert client.delete(path, headers=world["a"]).status_code == 403
    updated = client.put(path, headers=world["b"], json=payload)
    assert updated.status_code == 200
    assert updated.json()["created_at"] == memory["created_at"]
    assert updated.json()["content"] == "수정한 기억"
    assert client.delete(path, headers=world["b"]).status_code == 204
    assert client.get(path, headers=world["b"]).status_code == 404
    assert client.get(f"/groups/{gid}/map", headers=world["a"]).json()["items"] == []


def test_cross_group_place_and_record_ids_cannot_be_reused(world):
    client, gid = world["client"], world["group"]["id"]
    second = client.post("/groups", headers=world["a"], json={"name": "동네 친구"}).json()
    gid2 = second["id"]
    memory = add_memory(world)
    payload = {"place_id": world["place"]["id"], "content": "다른 모임", "visited_on": "2024-01-01"}
    assert client.post(f"/groups/{gid2}/memories", headers=world["a"], json=payload).status_code == 404
    assert client.get(f"/groups/{gid2}/memories/{memory['id']}", headers=world["a"]).status_code == 404
    assert client.get(f"/groups/{gid2}/memories?place_id={payload['place_id']}", headers=world["a"]).status_code == 404
    assert client.get(f"/groups/{gid2}/map", headers=world["a"]).json()["total"] == 0
    assert client.get(f"/groups/{gid}/map", headers=world["a"]).json()["total"] == 1


def test_author_spoofing_future_dates_blank_content_and_coordinates(world):
    client, gid = world["client"], world["group"]["id"]
    valid = {"place_id": world["place"]["id"], "content": "정상 글", "visited_on": "2024-01-01"}
    for change in [{"author_id": world["bob"]["id"]}, {"user_id": world["bob"]["id"]},
                   {"visited_on": str(today_in_korea() + timedelta(days=1))}, {"content": "   "}, {"place_id": 0}]:
        assert client.post(f"/groups/{gid}/memories", headers=world["a"], json=valid | change).status_code == 422
    for latitude in [91, -91, "NaN"]:
        response = client.post(f"/groups/{gid}/places", headers=world["a"], json={
            "name": "장소", "address": "주소", "latitude": latitude, "longitude": 127,
        })
        assert response.status_code == 422
    memory = add_memory(world)
    assert memory["author"]["id"] == world["alice"]["id"]


def test_search_filters_and_pagination(world):
    client, gid = world["client"], world["group"]["id"]
    for visited_on in ["2024-01-01", "2024-02-01", "2024-03-01"]:
        add_memory(world, visited_on=visited_on)
    page = client.get(f"/groups/{gid}/memories?order=oldest&offset=1&limit=1", headers=world["a"]).json()
    assert page["total"] == 3 and page["items"][0]["visited_on"] == "2024-02-01"
    filtered = client.get(f"/groups/{gid}/memories?date_from=2024-02-01&date_to=2024-02-01", headers=world["a"]).json()
    assert filtered["total"] == 1
    assert client.get(f"/groups/{gid}/memories?date_from=2025-01-01&date_to=2024-01-01", headers=world["a"]).status_code == 400
    assert client.get(f"/groups/{gid}/memories?limit=101", headers=world["a"]).status_code == 422
    assert client.get(f"/groups/{gid}/memories?offset=-1", headers=world["a"]).status_code == 422
    assert client.get(f"/groups/{gid}/places", params={"query": "테스트"}, headers=world["a"]).json()["total"] == 1
    assert client.get(f"/groups/{gid}/places", params={"query": "없는장소"}, headers=world["a"]).json()["total"] == 0
    duplicate = world["place"].copy()
    duplicate.pop("id")
    duplicate.pop("group_id")
    assert client.post(f"/groups/{gid}/places", headers=world["a"], json=duplicate).status_code == 409


def test_concurrent_registration_of_memories_keeps_unique_ids(world):
    def create_one(index):
        return add_memory(world, content=f"동시 기록 {index}")["id"]
    with ThreadPoolExecutor(max_workers=4) as pool:
        ids = list(pool.map(create_one, range(12)))
    assert len(set(ids)) == 12
    pins = world["client"].get(f"/groups/{world['group']['id']}/map", headers=world["a"]).json()
    assert pins["items"][0]["memory_count"] == 12


def test_restarting_service_resets_memory_storage(world):
    with TestClient(create_app()) as fresh_client:
        assert fresh_client.get("/groups", headers=world["a"]).status_code == 401
