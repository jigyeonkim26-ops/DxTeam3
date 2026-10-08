import pytest
from sqlalchemy.orm import Session

from app.record_models import GroupMember, MemoryGroup, Place, Record, RecordGroup
from test_records import world  # Reuse the isolated DB and real login fixture.


@pytest.fixture
def map_world(world):
    client, engine, _, headers = world
    with Session(engine) as db:
        db.add(MemoryGroup(id=30, name="Second joined group"))
        db.add(GroupMember(group_id=30, user_id=1))
        for place_id in range(12, 18):
            db.add(Place(id=place_id, provider="kakao", external_place_id=str(9000 + place_id),
                         name=f"Place {place_id}", address="Address", latitude=35.1107137,
                         longitude=126.8778041))
        db.flush()
        # Own private, other's private (even linked), joined shared, unjoined
        # shared, own shared to an unjoined group, and unshared non-private.
        cases = [(1, 12, True, []), (2, 13, True, [10]),
                 (2, 14, False, [10, 30, 20]), (3, 15, False, [20]),
                 (1, 12, False, [20]), (2, 16, False, []),
                 (2, 14, False, [10]), (1, 17, True, [])]
        for author, place, private, groups in cases:
            record = Record(author_id=author, place_id=place, is_private=private,
                            content="", emotion="good")
            db.add(record)
            db.flush()
            db.add_all([RecordGroup(record_id=record.id, group_id=g) for g in groups])
        db.commit()
    return client, headers


def pins(map_world, query=""):
    client, headers = map_world
    response = client.get("/map/places" + query, headers=headers[1])
    assert response.status_code == 200
    return response.json()


def test_own_records_and_internal_place_ids(map_world):
    result = pins(map_world)
    assert [p["place_id"] for p in result] == [12, 14, 17]
    assert result[0] == dict(place_id=12, name="Place 12", address="Address",
                           latitude=35.1107137, longitude=126.8778041, record_count=1)


def test_other_private_records_excluded_even_with_group_link(map_world):
    assert 13 not in [p["place_id"] for p in pins(map_world)]


def test_joined_group_records_visible_without_duplicate_counts(map_world):
    result = [p for p in pins(map_world) if p["place_id"] == 14]
    assert len(result) == 1
    assert result[0]["record_count"] == 2


def test_unjoined_and_unshared_records_excluded(map_world):
    assert {15, 16}.isdisjoint(p["place_id"] for p in pins(map_world))


def test_query_user_id_cannot_change_identity(map_world):
    assert pins(map_world, "?user_id=3") == pins(map_world)


@pytest.mark.parametrize("authorization", [None, "Bearer invalid-token"])
def test_authentication_required(map_world, authorization):
    client, _ = map_world
    headers = {} if authorization is None else {"Authorization": authorization}
    assert client.get("/map/places", headers=headers).status_code == 401


def test_no_visible_records_returns_empty_array(world):
    client, _, _, headers = world
    response = client.get("/map/places", headers=headers[1])
    assert response.status_code == 200
    assert response.json() == []
