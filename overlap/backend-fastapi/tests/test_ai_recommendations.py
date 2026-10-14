from datetime import date
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session
from sqlalchemy.pool import QueuePool, StaticPool

from app.ai_recommendation_errors import AIResponseError, InvalidRecommendationError
from app.ai_recommendations import _infer_region, _invalidate_empty_session
from app.ai_recommendation_models import (
    PlaceCandidate, PlaceCandidateResponse, PlaceRecommendationResponse, PreferenceKeyword, PreferenceKeywordResponse,
    RecommendedPlace,
)
from app.db import Base, get_db
from app.db_models import User
from app.main import create_app
from app.record_models import Place, Record
from app.recommendation_record_adapter import RecordRecommendationAdapter
from app.security import hash_password


class Keywords:
    def __init__(self):
        self.records = None

    def extract_keywords(self, records):
        self.records = records
        return PreferenceKeywordResponse(keywords=[PreferenceKeyword(keyword="노을", score=0.95)])


class Search:
    def __init__(self):
        self.keywords = self.records = None

    def search_candidates(self, keywords, records):
        self.keywords, self.records = keywords, records
        return PlaceCandidateResponse(candidates=[PlaceCandidate(
            name="광암교", address=None, latitude=None, longitude=None, matched_keywords=["노을"],
            summary="노을을 볼 수 있는 산책 장소", source_url="https://example.test/bridge",
        )])


class Verification:
    def verify(self, hints, keywords, records):
        return PlaceCandidateResponse(candidates=[PlaceCandidate(
            kakao_place_id="12345", name="광암교", address="광주광역시 남구",
            latitude=35.14, longitude=126.91, matched_keywords=["노을"],
            summary="노을을 볼 수 있는 산책 장소. 카카오에서 이름과 위치를 확인했습니다.",
            source_url="https://place.map.kakao.com/12345",
        )])


class Ranking:
    def __init__(self):
        self.records = self.keywords = self.candidates = None

    def recommend(self, records, keywords, candidates):
        self.records, self.keywords, self.candidates = records, keywords, candidates
        candidate = candidates.candidates[0]
        return PlaceRecommendationResponse(recommendations=[RecommendedPlace(
            rank=1, kakao_place_id=candidate.kakao_place_id,
            name=candidate.name, address=candidate.address, latitude=candidate.latitude,
            longitude=candidate.longitude, match_score=0.95, matched_keywords=["노을"],
            reason="노을을 선호한 기록과 맞습니다.", source_url=candidate.source_url,
        )])


class NoRecommendationImages:
    def enrich(self, db, user_id, response):
        return response


def test_inferred_region_keeps_the_most_frequent_second_level_locality():
    from types import SimpleNamespace

    records = [
        SimpleNamespace(address="전남광주통합특별시 광산구 월계동"),
        SimpleNamespace(address="전남광주통합특별시 광산구 수완동"),
        SimpleNamespace(address="전남광주통합특별시 여수시 학동"),
    ]

    assert _infer_region(records) == "전남광주통합특별시 광산구"


def test_legacy_empty_recommendation_session_is_invalidated():
    key = (7, "fingerprint")
    sessions = {key: {"recommendations": [], "first": []}}

    assert _invalidate_empty_session(sessions, key) is True
    assert key not in sessions


def test_populated_recommendation_session_is_not_invalidated():
    key = (7, "fingerprint")
    entry = {"recommendations": [object()], "first": [object()]}
    sessions = {key: entry}

    assert _invalidate_empty_session(sessions, key) is False
    assert sessions[key] is entry


@pytest.fixture
def world():
    engine = create_engine("sqlite://", poolclass=StaticPool, connect_args={"check_same_thread": False})
    Base.metadata.create_all(engine)
    with Session(engine) as db:
        db.add_all([
            User(id=1, email="one@example.test", nickname="one", gender="female", birth_date=date(1990, 1, 1), password_hash=hash_password("password-123")),
            User(id=2, email="two@example.test", nickname="two", gender="female", birth_date=date(1990, 1, 1), password_hash=hash_password("password-123")),
            User(id=3, email="three@example.test", nickname="three", gender="female", birth_date=date(1990, 1, 1), password_hash=hash_password("password-123")),
            Place(id=1, provider="kakao", external_place_id="1", name="사직공원", address="광주광역시 남구", road_address=None, latitude=35.14, longitude=126.91),
        ])
        db.add_all([
            Record(author_id=1, place_id=1, content="노을이 예쁘고 조용해서 좋았어요", emotion="excellent", is_private=True),
            Record(author_id=1, place_id=1, content="산책하기 좋았어요", emotion="good", is_private=True),
            Record(author_id=1, place_id=1, content="괜찮았어요", emotion="okay", is_private=True),
            Record(author_id=1, place_id=1, content="제외", emotion="neutral", is_private=True),
            Record(author_id=1, place_id=1, content="제외", emotion="disappointed", is_private=True),
            Record(author_id=1, place_id=1, content="제외", emotion="poor", is_private=True),
            Record(author_id=2, place_id=1, content="다른 사용자", emotion="excellent", is_private=True),
        ])
        db.commit()
    keywords, search, ranking = Keywords(), Search(), Ranking()
    api = create_app(use_db_auth=True, recommendation_adapter=RecordRecommendationAdapter(),
                     preference_service=keywords, place_search_service=search,
                     place_verification_service=Verification(), place_recommendation_service=ranking,
                     recommendation_image_service=NoRecommendationImages())
    def session():
        with Session(engine) as db:
            yield db
    api.dependency_overrides[get_db] = session
    with TestClient(api) as client:
        tokens = {}
        for user in ("one", "three"):
            token = client.post("/auth/login", json={"email": f"{user}@example.test", "password": "password-123"}).json()["access_token"]
            tokens[user] = {"Authorization": "Bearer " + token}
        yield client, tokens, keywords, search, ranking
    engine.dispose()


def test_recommendations_use_only_current_users_positive_records(world):
    client, headers, keywords, search, ranking = world
    response = client.get("/ai/recommendations", headers=headers["one"])
    assert response.status_code == 200, response.text
    assert [item.content for item in keywords.records] == ["괜찮았어요", "산책하기 좋았어요", "노을이 예쁘고 조용해서 좋았어요"]
    assert all(item.user_id == 1 for item in keywords.records)
    assert search.keywords[0].keyword == "노을"
    assert ranking.candidates.candidates[0].kakao_place_id == "12345"
    result = response.json()["recommendations"]
    assert len(result) == 1 and result[0]["name"] == "광암교"
    assert result[0]["kakao_place_id"] == "12345"
    assert result[0]["latitude"] == 35.14 and result[0]["longitude"] == 126.91
    assert result[0]["image_url"] is None
    assert result[0]["image_origin_type"] == "placeholder"


def test_refresh_uses_only_suitable_candidates_then_returns_original_in_order(world, monkeypatch):
    def verified_pool(self, hints, keywords, records):
        return PlaceCandidateResponse(candidates=[
            PlaceCandidate(
                kakao_place_id=place_id,
                name=f"verified-place-{index}",
                address="region district",
                latitude=35.0 + index / 1000,
                longitude=126.0 + index / 1000,
                matched_keywords=["노을"],
                summary=("노을 산책 장소" if index in (0, 1, 2, 3) else "일반 장소"),
                source_url=f"https://place.map.kakao.com/{place_id}",
            )
            for index, place_id in enumerate(("12345", "23456", "34567", "45678", "56789"))
        ])

    def rank_all(self, records, keywords, candidates):
        self.records, self.keywords, self.candidates = records, keywords, candidates
        return PlaceRecommendationResponse(recommendations=[
            RecommendedPlace(
                rank=index + 1, kakao_place_id=item.kakao_place_id,
                name=item.name, address=item.address, latitude=item.latitude,
                longitude=item.longitude, match_score=0.8,
                matched_keywords=["노을"], reason=f"노을 기록과 관련된 장소 {index + 1}",
                source_url=item.source_url,
            )
            for index, item in enumerate(candidates.candidates)
        ])

    monkeypatch.setattr(Verification, "verify", verified_pool)
    monkeypatch.setattr(Ranking, "recommend", rank_all)
    client, headers, _, _, ranking = world
    first = client.get("/ai/recommendations", headers=headers["one"])
    assert first.status_code == 200, first.text
    assert [item["kakao_place_id"] for item in first.json()["recommendations"]] == ["12345", "23456", "34567"]
    assert [item.kakao_place_id for item in ranking.candidates.candidates] == ["12345", "23456", "34567", "45678"]

    second = client.get("/ai/recommendations?refresh=true", headers=headers["one"])
    assert second.status_code == 200, second.text
    assert [item["kakao_place_id"] for item in second.json()["recommendations"]] == ["45678"]

    returned = client.get("/ai/recommendations?refresh=true", headers=headers["one"])
    assert returned.status_code == 200, returned.text
    assert [item["kakao_place_id"] for item in returned.json()["recommendations"]] == ["12345", "23456", "34567"]
    assert [item["reason"] for item in returned.json()["recommendations"]] == [item["reason"] for item in first.json()["recommendations"]]
    assert [(item["kakao_place_id"], item["latitude"], item["longitude"]) for item in returned.json()["recommendations"]] == [
        (item["kakao_place_id"], item["latitude"], item["longitude"])
        for item in first.json()["recommendations"]
    ]


def test_unsuitable_verified_places_are_not_recommended(world, monkeypatch):
    def unrelated(self, hints, keywords, records):
        return PlaceCandidateResponse(candidates=[PlaceCandidate(
            kakao_place_id="99999", name="일반 주차장", address="광주광역시 남구",
            latitude=35.14, longitude=126.91, matched_keywords=["노을"],
            summary="카카오 장소 검색에서 확인된 주차장", source_url="https://place.map.kakao.com/99999",
        )])

    monkeypatch.setattr(Verification, "verify", unrelated)
    client, headers, _, _, ranking = world
    response = client.get("/ai/recommendations", headers=headers["one"])
    assert response.status_code == 200, response.text
    assert response.json()["recommendations"] == []
    assert ranking.candidates is None


def test_semantic_source_evidence_qualifies_verified_place_without_exact_keyword(world, monkeypatch):
    def semantically_relevant(self, hints, keywords, records):
        return PlaceCandidateResponse(candidates=[PlaceCandidate(
            kakao_place_id="77777", name="사직공원", address="광주광역시 남구",
            latitude=35.14, longitude=126.91, matched_keywords=[],
            summary="해질녘 전망이 좋고 둘레길을 걸으며 도심 풍경을 볼 수 있는 공원입니다.",
            source_url="https://place.map.kakao.com/77777",
        )])

    monkeypatch.setattr(Verification, "verify", semantically_relevant)
    client, headers, _, _, ranking = world
    response = client.get("/ai/recommendations", headers=headers["one"])

    assert response.status_code == 200, response.text
    result = response.json()["recommendations"]
    assert len(result) == 1
    assert result[0]["kakao_place_id"] == "77777"
    assert result[0]["name"] == "사직공원"
    assert ranking.candidates.candidates[0].name == "사직공원"


def test_scenic_park_can_match_sunset_preference_without_literal_sunset_word(world, monkeypatch):
    def indirect_scenic_evidence(self, hints, keywords, records):
        return PlaceCandidateResponse(candidates=[PlaceCandidate(
            kakao_place_id="77778", name="사직공원", address="광주광역시 서구",
            latitude=35.14, longitude=126.91, matched_keywords=[],
            summary="탁 트인 풍경을 감상할 수 있는 공원으로 알려져 있습니다.",
            source_url="https://place.map.kakao.com/77778",
        )])

    monkeypatch.setattr(Verification, "verify", indirect_scenic_evidence)
    client, headers, _, _, ranking = world
    response = client.get("/ai/recommendations", headers=headers["one"])

    assert response.status_code == 200, response.text
    assert [item["kakao_place_id"] for item in response.json()["recommendations"]] == ["77778"]
    assert ranking.candidates.candidates[0].name == "사직공원"


def test_generic_kakao_fallback_evidence_still_does_not_qualify(world, monkeypatch):
    def generic_kakao_result(self, hints, keywords, records):
        return PlaceCandidateResponse(candidates=[PlaceCandidate(
            kakao_place_id="88888", name="사직공원", address="광주광역시 남구",
            latitude=35.14, longitude=126.91, matched_keywords=["노을"],
            summary="광주광역시의 카카오 장소 검색에서 확인된 장소",
            source_url="https://place.map.kakao.com/88888",
        )])

    monkeypatch.setattr(Verification, "verify", generic_kakao_result)
    client, headers, _, _, ranking = world
    response = client.get("/ai/recommendations", headers=headers["one"])

    assert response.status_code == 200, response.text
    assert response.json()["recommendations"] == []
    assert ranking.candidates is None


def test_refresh_rebuilds_session_after_positive_record_changes(world):
    client, headers, keywords, search, ranking = world
    first = client.get("/ai/recommendations", headers=headers["one"])
    assert first.status_code == 200
    record = keywords.records[0]
    changed_content = "노을이 보이는 잔잔한 산책길이 좋았어요"
    update = client.patch(
        f"/records/{record.record_id}",
        headers=headers["one"],
        json={"content": changed_content},
    )
    assert update.status_code == 200, update.text

    refreshed = client.get("/ai/recommendations?refresh=true", headers=headers["one"])
    assert refreshed.status_code == 200, refreshed.text
    assert changed_content in [item.content for item in keywords.records]
    assert search.records == keywords.records
    assert ranking.candidates is not None


def test_empty_ranking_uses_verified_evidence_fallback_and_caches_nonempty_result(world, monkeypatch):
    calls = {"ranking": 0}

    def empty_ranking(self, records, keywords, candidates):
        calls["ranking"] += 1
        self.records, self.keywords, self.candidates = records, keywords, candidates
        return PlaceRecommendationResponse(recommendations=[])

    monkeypatch.setattr(Ranking, "recommend", empty_ranking)
    client, headers, _, search, _ = world

    first = client.get("/ai/recommendations", headers=headers["one"])
    second = client.get("/ai/recommendations?refresh=true", headers=headers["one"])

    assert first.status_code == second.status_code == 200
    assert len(first.json()["recommendations"]) == len(second.json()["recommendations"]) == 1
    assert first.json()["recommendations"][0]["kakao_place_id"] == "12345"
    assert first.json()["recommendations"][0]["matched_keywords"]
    assert calls["ranking"] == 1
    assert search.records is not None


def test_malformed_ranking_uses_only_already_qualified_verified_places(world, monkeypatch):
    def malformed(self, records, keywords, candidates):
        raise AIResponseError("invalid model response")

    monkeypatch.setattr(Ranking, "recommend", malformed)
    client, headers, _, _, _ = world
    response = client.get("/ai/recommendations", headers=headers["one"])

    assert response.status_code == 200, response.text
    result = response.json()["recommendations"]
    assert len(result) == 1
    assert result[0]["kakao_place_id"] == "12345"
    assert result[0]["matched_keywords"] == ["노을"]


def test_nonempty_recommendation_session_remains_cached(world, monkeypatch):
    calls = {"ranking": 0}
    original = Ranking.recommend

    def count_ranking(self, records, keywords, candidates):
        calls["ranking"] += 1
        return original(self, records, keywords, candidates)

    monkeypatch.setattr(Ranking, "recommend", count_ranking)
    client, headers, _, _, _ = world

    first = client.get("/ai/recommendations", headers=headers["one"])
    cached = client.get("/ai/recommendations", headers=headers["one"])

    assert first.status_code == cached.status_code == 200
    assert len(first.json()["recommendations"]) == 1
    assert cached.json() == first.json()
    assert calls["ranking"] == 1


def test_recommendation_session_is_isolated_by_authenticated_user(world):
    client, headers, keywords, _, _ = world
    first = client.get("/ai/recommendations", headers=headers["one"])
    assert first.status_code == 200
    token = client.post(
        "/auth/login",
        json={"email": "two@example.test", "password": "password-123"},
    ).json()["access_token"]
    other_user = {"Authorization": f"Bearer {token}"}

    response = client.get("/ai/recommendations", headers=other_user)
    assert response.status_code == 200, response.text
    assert keywords.records and all(item.user_id == 2 for item in keywords.records)


def test_no_positive_records_returns_empty_without_provider_calls(world):
    client, headers, keywords, _, _ = world
    response = client.get("/ai/recommendations", headers=headers["three"])
    assert response.status_code == 200 and response.json() == {"recommendations": []}
    assert keywords.records is None


def test_openrouter_ranking_rejects_outside_candidate_without_network():
    from app.openrouter_place_recommendation_service import OpenRouterPlaceRecommendationService
    class Response:
        def raise_for_status(self): pass
        def json(self): return {"choices": [{"message": {"content": '{"recommendations":[{"kakao_place_id":"outside","match_score":1,"matched_keywords":["노을"],"reason":"실패"}]}'}}]}
    record = type("RecordInput", (), {"content": "노을", "emotion_meaning": "최고", "place_name": "사직공원"})()
    candidate = PlaceCandidate(kakao_place_id="12345", name="광암교", summary="노을", source_url="https://bridge")
    with pytest.raises(InvalidRecommendationError):
        OpenRouterPlaceRecommendationService(api_key="test", model="test", post_json=lambda *_, **__: Response()).recommend(
            [record], [PreferenceKeyword(keyword="노을", score=1)], [candidate]
        )


def test_ai_provider_calls_do_not_hold_db_connection():
    engine = create_engine(
        "sqlite://",
        poolclass=QueuePool,
        pool_size=1,
        max_overflow=0,
        pool_timeout=1,
        connect_args={"check_same_thread": False},
    )
    Base.metadata.create_all(engine)
    with Session(engine) as db:
        db.add(User(
            id=901, email="pool@example.test", nickname="pool", gender="female",
            birth_date=date(1990, 1, 1), password_hash=hash_password("pool-password"),
        ))
        place = Place(
            id=901, provider="kakao", external_place_id="901", name="사직공원",
            address="광주광역시 남구", road_address=None, latitude=35.14, longitude=126.91,
        )
        db.add(place)
        db.flush()
        db.add(Record(
            author_id=901, place_id=901, content="노을 산책", emotion="good", is_private=True,
        ))
        db.commit()

    concurrent_provider_calls = Barrier(2)

    class PoolProbeKeywords:
        def extract_keywords(self, records):
            # A second checkout must work while this request's provider stage runs.
            with engine.connect() as connection:
                assert connection.execute(text("SELECT 1")).scalar_one() == 1
            concurrent_provider_calls.wait(timeout=5)
            return PreferenceKeywordResponse(keywords=[PreferenceKeyword(keyword="노을", score=0.9)])

    api = create_app(
        use_db_auth=True,
        recommendation_adapter=RecordRecommendationAdapter(),
        preference_service=PoolProbeKeywords(),
        place_search_service=Search(),
        place_verification_service=Verification(),
        place_recommendation_service=Ranking(),
        recommendation_image_service=NoRecommendationImages(),
    )

    def db_session():
        with Session(engine) as db:
            yield db

    api.dependency_overrides[get_db] = db_session
    try:
        with TestClient(api) as client:
            login = client.post(
                "/auth/login",
                json={"email": "pool@example.test", "password": "pool-password"},
            )
            assert login.status_code == 200, login.text
            headers = {"Authorization": f"Bearer {login.json()['access_token']}"}
            with ThreadPoolExecutor(max_workers=2) as executor:
                futures = [
                    executor.submit(client.get, "/ai/recommendations", headers=headers)
                    for _ in range(2)
                ]
                responses = [future.result(timeout=10) for future in futures]
            assert all(response.status_code == 200 for response in responses)
            assert all(len(response.json()["recommendations"]) == 1 for response in responses)
        assert engine.pool.checkedout() == 0
    finally:
        engine.dispose()
