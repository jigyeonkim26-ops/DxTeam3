from sqlalchemy import func, select
from sqlalchemy.orm import Session

import app.saved_places as saved_api
from app.record_models import Place, Record, SavedPlace
from test_records import world


SNAPSHOT = {"name": "양림동 펭귄마을", "address": "광주광역시 남구 양림동"}


def kakao_result():
    return {
        "kakao_place_id": "12345", "name": SNAPSHOT["name"],
        "address": SNAPSHOT["address"], "latitude": 35.14,
        "longitude": 126.91, "place_url": "https://place.map.kakao.com/12345",
    }


def test_lookup_is_read_only_and_saving_creates_only_place_and_bookmark(world, monkeypatch):
    client, engine, _, headers = world
    calls = []
    monkeypatch.setattr(saved_api, "search_places", lambda query, **kwargs: calls.append(query) or [kakao_result()])

    response = client.get("/places/kakao/12345", headers=headers[1])
    assert response.json() == {"place_id": None, "saved": False, "record_count": 0}
    with Session(engine) as db:
        assert db.scalar(select(func.count()).select_from(Place)) == 0

    saved = client.post("/places/kakao/12345/saved", headers=headers[1], json=SNAPSHOT)
    assert saved.status_code == 200, saved.text
    place_id = saved.json()["place_id"]
    assert saved.json()["saved"] is True
    assert calls == ["광주광역시 양림동 펭귄마을"]
    with Session(engine) as db:
        place = db.get(Place, place_id)
        assert (place.provider, place.external_place_id, place.name) == ("kakao", "12345", SNAPSHOT["name"])
        assert (float(place.latitude), float(place.longitude)) == (35.14, 126.91)
        assert db.scalar(select(func.count()).select_from(Record)) == 0

    assert client.post("/places/kakao/12345/saved", headers=headers[1], json=SNAPSHOT).json()["saved_count"] == 1
    assert client.post("/places/kakao/12345/saved", headers=headers[2], json=SNAPSHOT).json()["place_id"] == place_id
    assert len(calls) == 1
    assert client.get("/places/kakao/12345", headers=headers[2]).json()["saved"] is True
    assert client.get("/places/saved", headers=headers[1]).json()["items"][0]["name"] == SNAPSHOT["name"]

    assert client.delete(f"/places/{place_id}/saved", headers=headers[1]).json()["saved"] is False
    assert client.get("/places/kakao/12345", headers=headers[2]).json()["saved"] is True
    with Session(engine) as db:
        assert db.get(Place, place_id) is not None
        assert db.scalar(select(func.count()).select_from(SavedPlace)) == 1


def test_existing_kakao_place_and_visible_records_are_reused(world, monkeypatch):
    client, engine, _, headers = world
    with Session(engine) as db:
        db.add(Place(id=55, provider="kakao", external_place_id="12345", name=SNAPSHOT["name"],
                     address=SNAPSHOT["address"], latitude=35.14, longitude=126.91))
        db.add(Record(author_id=1, place_id=55, content="산책", emotion="good", is_private=True))
        db.commit()
    monkeypatch.setattr(saved_api, "search_places", lambda *_args, **_kwargs: (_ for _ in ()).throw(AssertionError("Kakao called")))
    assert client.get("/places/kakao/12345", headers=headers[1]).json() == {
        "place_id": 55, "saved": False, "record_count": 1,
    }
    assert client.get("/places/kakao/12345", headers=headers[2]).json()["record_count"] == 0
    assert client.post("/places/kakao/12345/saved", headers=headers[1], json=SNAPSHOT).json()["place_id"] == 55
    with Session(engine) as db:
        assert db.scalar(select(func.count()).select_from(Place)) == 1
        assert db.scalar(select(func.count()).select_from(Record)) == 1


def test_unverified_kakao_result_cannot_create_place(world, monkeypatch):
    client, engine, _, headers = world
    monkeypatch.setattr(saved_api, "search_places", lambda *_args, **_kwargs: [
        {**kakao_result(), "kakao_place_id": "99999"},
    ])
    response = client.post("/places/kakao/12345/saved", headers=headers[1], json=SNAPSHOT)
    assert response.status_code == 422
    with Session(engine) as db:
        assert db.scalar(select(func.count()).select_from(Place)) == 0
        assert db.scalar(select(func.count()).select_from(SavedPlace)) == 0
