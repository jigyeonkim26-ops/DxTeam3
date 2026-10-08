import pytest
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.record_models import GroupMember, RecordLike
from test_records import create, world


def request(world, method, record_id, user=1, query="", **kwargs):
    return world[0].request(method, f"/records/{record_id}/likes{query}",
                            headers=world[3][user], **kwargs)


def test_add_like_and_get_count_and_viewer_state(world):
    record_id = create(world).json()["id"]
    empty = dict(record_id=record_id, like_count=0, liked=False)
    assert request(world, "GET", record_id).json() == empty
    response = request(world, "POST", record_id)
    assert response.status_code == 200
    assert response.json() == dict(record_id=record_id, like_count=1, liked=True)
    assert request(world, "GET", record_id).json() == response.json()
    assert request(world, "GET", record_id, user=2).json() == dict(
        record_id=record_id, like_count=1, liked=False)
    assert request(world, "POST", record_id, user=2).json() == dict(
        record_id=record_id, like_count=2, liked=True)


def test_cancel_like_is_idempotent_and_only_removes_current_users_like(world):
    record_id = create(world).json()["id"]
    request(world, "POST", record_id)
    request(world, "POST", record_id, user=2)
    for _ in range(2):
        response = request(world, "DELETE", record_id)
        assert response.status_code == 200
        assert response.json() == dict(record_id=record_id, like_count=1, liked=False)
    assert request(world, "GET", record_id, user=2).json()["liked"] is True


def test_duplicate_like_and_composite_primary_key(world):
    record_id = create(world).json()["id"]
    for _ in range(2):
        response = request(world, "POST", record_id)
        assert response.status_code == 200
        assert response.json()["like_count"] == 1
    assert set(RecordLike.__table__.primary_key.columns.keys()) == {"record_id", "user_id"}
    with Session(world[1]) as db:
        assert db.scalar(select(func.count()).select_from(RecordLike)) == 1
        db.add(RecordLike(record_id=record_id, user_id=1))
        with pytest.raises(IntegrityError):
            db.commit()
        db.rollback()


def test_client_user_id_does_not_override_token_identity(world):
    record_id = create(world).json()["id"]
    assert request(world, "POST", record_id, query="?user_id=2", json={"user_id": 2}).status_code == 200
    assert request(world, "GET", record_id, user=2, query="?user_id=1").json()["liked"] is False
    assert request(world, "DELETE", record_id, user=2, query="?user_id=1").json()["like_count"] == 1
    with Session(world[1]) as db:
        assert db.get(RecordLike, (record_id, 1)) is not None
        assert db.get(RecordLike, (record_id, 2)) is None


@pytest.mark.parametrize("method", ["GET", "POST", "DELETE"])
def test_missing_record_returns_404(world, method):
    assert request(world, method, 999999).status_code == 404


@pytest.mark.parametrize("method", ["GET", "POST", "DELETE"])
@pytest.mark.parametrize("private,viewer", [(True, 2), (False, 3)])
def test_inaccessible_record_returns_404_without_mutating_likes(world, method, private, viewer):
    record_id = create(world, private=private).json()["id"]
    assert request(world, "POST", record_id).status_code == 200
    assert request(world, method, record_id, user=viewer).status_code == 404
    assert request(world, "GET", record_id).json()["like_count"] == 1


def test_membership_revocation_blocks_likes(world):
    record_id = create(world).json()["id"]
    assert request(world, "POST", record_id, user=2).status_code == 200
    with Session(world[1]) as db:
        db.delete(db.get(GroupMember, (10, 2)))
        db.commit()
    for method in ("GET", "POST", "DELETE"):
        assert request(world, method, record_id, user=2).status_code == 404


@pytest.mark.parametrize("method", ["GET", "POST", "DELETE"])
@pytest.mark.parametrize("headers", [{}, {"Authorization": "Bearer invalid"}])
def test_unauthenticated_requests_rejected(world, method, headers):
    record_id = create(world).json()["id"]
    assert world[0].request(method, f"/records/{record_id}/likes", headers=headers).status_code == 401
