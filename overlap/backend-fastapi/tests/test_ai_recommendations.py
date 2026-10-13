from datetime import date

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app.ai_recommendation_errors import InvalidRecommendationError
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
            summary="카카오에서 확인된 장소", source_url="https://place.map.kakao.com/12345",
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


def test_refresh_excludes_previous_verified_ids_and_reuses_pool_when_exhausted(world, monkeypatch):
    def verified_pool(self, hints, keywords, records):
        return PlaceCandidateResponse(candidates=[
            PlaceCandidate(
                kakao_place_id=place_id,
                name=f"verified-place-{index}",
                address="region district",
                latitude=35.0 + index / 1000,
                longitude=126.0 + index / 1000,
                matched_keywords=["interest"],
                summary="Kakao-verified candidate",
                source_url=f"https://place.map.kakao.com/{place_id}",
            )
            for index, place_id in enumerate(("12345", "23456", "34567", "45678"))
        ])

    monkeypatch.setattr(Verification, "verify", verified_pool)
    client, headers, _, _, ranking = world
    response = client.get(
        "/ai/recommendations?exclude_place_ids=12345,23456,34567",
        headers=headers["one"],
    )
    assert response.status_code == 200, response.text
    assert [item.kakao_place_id for item in ranking.candidates.candidates] == ["45678"]
    assert response.json()["recommendations"][0]["kakao_place_id"] == "45678"

    exhausted = client.get(
        "/ai/recommendations?exclude_place_ids=12345,23456,34567,45678&previous_place_ids=45678",
        headers=headers["one"],
    )
    assert exhausted.status_code == 200, exhausted.text
    assert [item.kakao_place_id for item in ranking.candidates.candidates] == [
        "12345", "23456", "34567",
    ]
    assert response.json()["recommendations"][0]["kakao_place_id"] != exhausted.json()["recommendations"][0]["kakao_place_id"]


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
