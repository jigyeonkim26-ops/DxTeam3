from datetime import date

from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app.ai_recommendation_models import PlaceRecommendationResponse, RecommendedPlace
from app.db import Base
from app.db_models import User
from app.main import create_app  # Import all existing model mappings for test metadata.
from app.recommendation_image_service import RecommendationImageService
from app.record_models import Place, Record, RecordPhoto
from app.security import hash_password


def _recommendation(*, name="죽녹원", address="전라남도 담양군 담양읍"):
    return PlaceRecommendationResponse(recommendations=[RecommendedPlace(
        kakao_place_id="12345", rank=1, name=name, address=address,
        latitude=35.3, longitude=126.9, match_score=0.9,
        matched_keywords=["산책"], reason="가상 취향 이유", source_url="https://place.test/12345",
    )])


def _database():
    engine = create_engine("sqlite://", poolclass=StaticPool, connect_args={"check_same_thread": False})
    Base.metadata.create_all(engine)
    return engine


def _add_user(db, user_id):
    db.add(User(
        id=user_id, email=f"user{user_id}@example.test", nickname=f"user{user_id}",
        gender="female", birth_date=date(1990, 1, 1), password_hash=hash_password("password-123"),
    ))


def test_accessible_record_photo_takes_priority_over_external_search():
    engine = _database()
    search_calls = []
    service = RecommendationImageService(search=lambda query: search_calls.append(query) or {})
    with Session(engine) as db:
        _add_user(db, 1)
        place = Place(
            id=1, provider="kakao", external_place_id="12345", name="죽녹원",
            address="전라남도 담양군 담양읍", road_address=None,
            latitude=35.3, longitude=126.9,
        )
        db.add(place)
        record = Record(author_id=1, place_id=1, content="기록", emotion="excellent", is_private=True)
        db.add(record)
        db.flush()
        db.add(RecordPhoto(
            record_id=record.id, object_key="private/record.jpg", mime_type="image/jpeg", sort_order=0,
        ))
        db.commit()

        result = service.enrich(db, 1, _recommendation()).recommendations[0]
        assert result.image_origin_type == "record"
        assert result.image_source == "overlap_record"
        assert result.image_url == f"/records/{record.id}/photos/1"
        assert search_calls == []
    engine.dispose()


def test_private_record_photo_is_not_exposed_to_another_user():
    engine = _database()
    service = RecommendationImageService(search=lambda query: {"documents": []})
    with Session(engine) as db:
        _add_user(db, 1)
        _add_user(db, 2)
        place = Place(
            id=1, provider="kakao", external_place_id="12345", name="죽녹원",
            address="전라남도 담양군 담양읍", road_address=None,
            latitude=35.3, longitude=126.9,
        )
        db.add(place)
        record = Record(author_id=1, place_id=1, content="비공개 기록", emotion="excellent", is_private=True)
        db.add(record)
        db.flush()
        db.add(RecordPhoto(record_id=record.id, object_key="private/record.jpg", mime_type="image/jpeg"))
        db.commit()

        result = service.enrich(db, 2, _recommendation()).recommendations[0]
        assert result.image_url is None
        assert result.image_origin_type == "placeholder"
    engine.dispose()


def test_external_image_requires_place_name_and_region_match_and_is_cached():
    engine = _database()
    queries = []

    def search(query):
        queries.append(query)
        return {"documents": [
            {
                "title": "죽녹원 산책 사진",
                "display_sitename": "전남 여행 기록",
                "thumbnail_url": "https://cdn.example.test/juknokwon.jpg",
                "image_url": "https://origin.example.test/juknokwon.jpg",
                "doc_url": "https://blog.example.test/juknokwon",
            },
        ]}

    service = RecommendationImageService(search=search)
    with Session(engine) as db:
        first = service.enrich(db, 1, _recommendation()).recommendations[0]
        second = service.enrich(db, 2, _recommendation()).recommendations[0]
        assert first.image_url == "https://cdn.example.test/juknokwon.jpg"
        assert first.image_origin_type == "external"
        assert first.image_source == "kakao_daum_image_search"
        assert first.image_credit == "전남 여행 기록"
        assert second.image_url == first.image_url
        assert queries == ["죽녹원 전라남도 담양군"]
    engine.dispose()


def test_external_image_accepts_exact_place_title_when_source_omits_locality():
    engine = _database()
    service = RecommendationImageService(search=lambda query: {"documents": [
        {
            "title": "죽녹원 방문 후기",
            "display_sitename": "여행 기록",
            "thumbnail_url": "https://cdn.example.test/juknokwon.jpg",
            "image_url": "https://origin.example.test/juknokwon.jpg",
            "doc_url": "https://blog.example.test/juknokwon",
        },
    ]})
    with Session(engine) as db:
        result = service.enrich(db, 1, _recommendation()).recommendations[0]
        assert result.image_url == "https://cdn.example.test/juknokwon.jpg"
        assert result.image_origin_type == "external"
    engine.dispose()


def test_partial_generic_name_does_not_match_a_different_branch():
    place = _recommendation().recommendations[0].model_copy(
        update={"name": "Cafe Gangnam branch"}
    )
    selected = RecommendationImageService._select_external(place, [{
        "title": "Cafe photo review",
        "display_sitename": "travel diary",
        "thumbnail_url": "https://cdn.example.test/other-branch.jpg",
        "image_url": "https://origin.example.test/other-branch.jpg",
        "doc_url": "https://blog.example.test/other-branch",
    }])
    assert selected is None


def test_negative_cache_can_be_cleared_after_provider_or_filter_change():
    engine = _database()
    calls = []

    def search(query):
        calls.append(query)
        return {"documents": [] if len(calls) == 1 else [{
            "title": "죽녹원",
            "display_sitename": "여행 기록",
            "thumbnail_url": "https://cdn.example.test/juknokwon.jpg",
            "image_url": "https://origin.example.test/juknokwon.jpg",
            "doc_url": "https://blog.example.test/juknokwon",
        }]}

    service = RecommendationImageService(search=search)
    with Session(engine) as db:
        first = service.enrich(db, 1, _recommendation()).recommendations[0]
        assert first.image_origin_type == "placeholder"
        service.clear_cache()
        second = service.enrich(db, 1, _recommendation()).recommendations[0]
        assert second.image_origin_type == "external"
        assert len(calls) == 2
    engine.dispose()


def test_unrelated_or_insecure_image_results_fall_back_to_placeholder():
    engine = _database()
    service = RecommendationImageService(search=lambda query: {"documents": [
        {
            "title": "죽녹원 방문기",
            "display_sitename": "서울 여행 블로그",
            "thumbnail_url": "http://images.example.test/wrong-region.jpg",
            "image_url": "http://images.example.test/wrong-region.jpg",
            "doc_url": "https://blog.example.test/post",
        },
    ]})
    with Session(engine) as db:
        result = service.enrich(db, 1, _recommendation()).recommendations[0]
        assert result.image_url is None
        assert result.image_origin_type == "placeholder"
    engine.dispose()


def test_image_provider_failure_does_not_fail_enrichment():
    engine = _database()

    def fail(_query):
        raise TimeoutError("offline test")

    service = RecommendationImageService(search=fail)
    with Session(engine) as db:
        result = service.enrich(db, 1, _recommendation()).recommendations[0]
        assert result.name == "죽녹원"
        assert result.image_origin_type == "placeholder"
    engine.dispose()
