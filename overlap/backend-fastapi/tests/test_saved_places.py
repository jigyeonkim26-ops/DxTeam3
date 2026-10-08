import pytest
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.record_models import Place, SavedPlace
from test_records import world


@pytest.fixture
def places(world):
    with Session(world[1]) as db:
        db.add_all([Place(id=i, name=f"Place {i}", address="Test address",
                          latitude=37.5, longitude=127.0) for i in (101, 102)])
        db.commit()
    return world


def request(places, method, place_id=101, user=1, query="", **kwargs):
    return places[0].request(method, f"/places/{place_id}/saved{query}",
                             headers=places[3][user], **kwargs)


def listing(places, user=1, query=""):
    return places[0].get("/places/saved" + query, headers=places[3][user])


def test_save_state_and_personal_count(places):
    assert request(places, "GET").json() == dict(place_id=101, saved=False, saved_count=0)
    response = request(places, "POST")
    assert response.status_code == 200
    assert response.json() == dict(place_id=101, saved=True, saved_count=1)
    assert request(places, "GET").json() == response.json()
    assert request(places, "POST", place_id=102).json()["saved_count"] == 2
    assert request(places, "GET", user=2).json() == dict(place_id=101, saved=False, saved_count=0)


def test_duplicate_save_and_composite_key(places):
    for _ in range(2):
        response = request(places, "POST")
        assert response.status_code == 200
        assert response.json()["saved_count"] == 1
    assert set(SavedPlace.__table__.primary_key.columns.keys()) == {"user_id", "place_id"}
    with Session(places[1]) as db:
        assert db.scalar(select(func.count()).select_from(SavedPlace)) == 1
        db.add(SavedPlace(user_id=1, place_id=101))
        with pytest.raises(IntegrityError):
            db.commit()
        db.rollback()


def test_unsave_is_repeatable_and_preserves_other_users(places):
    request(places, "POST")
    request(places, "POST", user=2)
    for _ in range(2):
        response = request(places, "DELETE")
        assert response.status_code == 200
        assert response.json() == dict(place_id=101, saved=False, saved_count=0)
    assert request(places, "GET", user=2).json()["saved"] is True


def test_list_pagination_and_user_isolation(places):
    request(places, "POST")
    request(places, "POST", place_id=102)
    request(places, "POST", user=2)
    response = listing(places)
    assert response.status_code == 200
    payload = response.json()
    assert payload["total"] == 2
    assert [p["place_id"] for p in payload["items"]] == [102, 101]
    assert payload["items"][0]["created_at"]
    assert payload["items"][0]["latitude"] == 37.5
    assert "user_id" not in payload["items"][0]
    page = listing(places, query="?limit=1&offset=1").json()
    assert page == dict(items=[payload["items"][1]], total=2, offset=1, limit=1)
    assert [p["place_id"] for p in listing(places, user=2).json()["items"]] == [101]
    assert listing(places, user=3).json() == dict(items=[], total=0, offset=0, limit=20)


def test_client_user_id_cannot_select_other_user(places):
    assert request(places, "POST", query="?user_id=2", json={"user_id": 2}).status_code == 200
    assert listing(places, user=2, query="?user_id=1").json()["items"] == []
    assert request(places, "GET", user=2, query="?user_id=1").json()["saved"] is False
    assert request(places, "DELETE", user=2, query="?user_id=1").status_code == 200
    assert request(places, "GET").json()["saved"] is True


@pytest.mark.parametrize("method", ["GET", "POST", "DELETE"])
def test_nonexistent_place(places, method):
    assert request(places, method, place_id=999999).status_code == 404


@pytest.mark.parametrize("method,path", [
    ("GET", "/places/saved"), ("GET", "/places/101/saved"),
    ("POST", "/places/101/saved"), ("DELETE", "/places/101/saved"),
])
@pytest.mark.parametrize("headers", [{}, {"Authorization": "Bearer invalid"}])
def test_authentication_required(places, method, path, headers):
    assert places[0].request(method, path, headers=headers).status_code == 401
