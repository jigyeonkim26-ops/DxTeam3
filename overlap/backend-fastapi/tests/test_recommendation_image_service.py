from datetime import date

from sqlalchemy import create_engine, text
from sqlalchemy.orm import Session
from sqlalchemy.pool import QueuePool, StaticPool

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


def test_provider_uses_kakao_blog_search_contract(monkeypatch):
    import app.recommendation_image_service as image_service_module

    captured = {}

    class Response:
        def raise_for_status(self):
            return None

        def json(self):
            return {"documents": []}

    def fake_get(url, *, headers, params, timeout):
        captured.update(url=url, headers=headers, params=params, timeout=timeout)
        return Response()

    monkeypatch.setattr(image_service_module, "KAKAO_REST_API_KEY", "test-key")
    monkeypatch.setattr(image_service_module.httpx, "get", fake_get)

    payload = RecommendationImageService()._search_kakao("죽녹원 전라남도 담양군")

    assert payload == {"documents": []}
    assert captured["url"] == "https://dapi.kakao.com/v2/search/blog"
    assert captured["headers"] == {"Authorization": "KakaoAK test-key"}
    assert captured["params"] == {
        "query": "죽녹원 전라남도 담양군",
        "size": RecommendationImageService.MAX_RESULTS,
        "sort": "accuracy",
    }


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


def test_external_blog_thumbnail_requires_place_name_and_region_and_is_cached():
    engine = _database()
    queries = []

    def search(query):
        queries.append(query)
        return {"documents": [
            {
                "title": "죽녹원 산책 사진",
                "contents": "전라남도 담양군 죽녹원에서 산책한 후기",
                "blogname": "전남 여행 기록",
                "thumbnail": "http://search3.kakaocdn.net/juknokwon.jpg",
                "url": "https://blog.example.test/juknokwon",
            },
        ]}

    service = RecommendationImageService(search=search)
    with Session(engine) as db:
        first = service.enrich(db, 1, _recommendation()).recommendations[0]
        second = service.enrich(db, 2, _recommendation()).recommendations[0]
        assert first.image_url == "http://search3.kakaocdn.net/juknokwon.jpg"
        assert first.image_origin_type == "external"
        assert first.image_source == "kakao_daum_blog_search"
        assert first.image_credit == "전남 여행 기록"
        assert second.image_url == first.image_url
        assert queries == ["죽녹원 전라남도 담양군"]
    engine.dispose()


def test_missing_title_can_use_contents_only_when_name_and_locality_match():
    engine = _database()
    service = RecommendationImageService(search=lambda query: {"documents": [
        {
            "title": "",
            "contents": "전라남도 담양군 죽녹원 방문 후기",
            "blogname": "여행 기록",
            "thumbnail": "https://cdn.example.test/juknokwon.jpg",
            "url": "https://blog.example.test/juknokwon",
        },
    ]})
    with Session(engine) as db:
        result = service.enrich(db, 1, _recommendation()).recommendations[0]
        assert result.image_url == "https://cdn.example.test/juknokwon.jpg"
        assert result.image_origin_type == "external"
    engine.dispose()


def test_exact_place_name_without_region_is_not_enough_to_select_thumbnail():
    selected, rejected = RecommendationImageService._select_external_with_diagnostics(
        _recommendation().recommendations[0], [{
            "title": "죽녹원 방문 후기",
            "contents": "산책하기 좋은 장소입니다.",
            "blogname": "여행 기록",
            "thumbnail": "https://cdn.example.test/juknokwon.jpg",
            "url": "https://blog.example.test/juknokwon",
        }]
    )
    assert selected is None
    assert rejected["region"] == 1


def test_same_place_name_from_another_region_is_rejected():
    selected, rejected = RecommendationImageService._select_external_with_diagnostics(
        _recommendation().recommendations[0], [{
            "title": "죽녹원 산책",
            "contents": "서울에서 찾은 죽녹원 전시 행사 후기",
            "blogname": "서울 여행 기록",
            "thumbnail": "https://cdn.example.test/wrong-region.jpg",
            "url": "https://blog.example.test/wrong-region",
        }]
    )
    assert selected is None
    assert rejected["region"] == 1


def test_image_search_schema_without_place_metadata_is_not_trusted():
    selected, rejected = RecommendationImageService._select_external_with_diagnostics(
        _recommendation().recommendations[0], [{
            # Kakao Image Search documents do not contain title/contents.
            "collection": "blog",
            "display_sitename": "Kakao source",
            "thumbnail_url": "https://cdn.example.test/unknown.jpg",
            "image_url": "https://origin.example.test/unknown.jpg",
            "doc_url": "https://blog.example.test/post",
        }]
    )
    assert selected is None
    assert rejected["missing_metadata"] == 1


def test_partial_generic_name_does_not_match_a_different_branch():
    place = _recommendation().recommendations[0].model_copy(
        update={"name": "Cafe Gangnam branch"}
    )
    selected = RecommendationImageService._select_external(place, [{
        "title": "Cafe photo review",
        "contents": "Cafe Gangnam branch photo review",
        "blogname": "travel diary",
        "thumbnail": "https://cdn.example.test/other-branch.jpg",
        "url": "https://blog.example.test/other-branch",
    }])
    assert selected is None


def test_negative_cache_can_be_cleared_after_provider_or_filter_change():
    engine = _database()
    calls = []

    def search(query):
        calls.append(query)
        return {"documents": [] if len(calls) == 1 else [{
            "title": "죽녹원",
            "contents": "전라남도 담양군 죽녹원 방문",
            "blogname": "여행 기록",
            "thumbnail": "https://cdn.example.test/juknokwon.jpg",
            "url": "https://blog.example.test/juknokwon",
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
            "contents": "전라남도 담양군 죽녹원 방문",
            "blogname": "서울 여행 블로그",
            "thumbnail": "http://images.example.test/wrong-region.jpg",
            "url": "https://blog.example.test/post",
        },
    ]})
    with Session(engine) as db:
        result = service.enrich(db, 1, _recommendation()).recommendations[0]
        assert result.image_url is None
        assert result.image_origin_type == "placeholder"
    engine.dispose()


def test_untrusted_cleartext_thumbnail_is_rejected():
    selected, rejected = RecommendationImageService._select_external_with_diagnostics(
        _recommendation().recommendations[0], [{
            "title": "죽녹원 방문기",
            "contents": "전라남도 담양군 죽녹원",
            "blogname": "여행 기록",
            "thumbnail": "http://images.example.test/wrong-host.jpg",
            "url": "https://blog.example.test/post",
        }]
    )
    assert selected is None
    assert rejected["url"] == 1


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


def test_image_provider_runs_after_read_transaction_returns_connection():
    engine = create_engine(
        "sqlite://",
        poolclass=QueuePool,
        pool_size=1,
        max_overflow=0,
        pool_timeout=0.1,
        connect_args={"check_same_thread": False},
    )
    Base.metadata.create_all(engine)
    provider_checked_out_connection = []

    def search(_query):
        assert engine.pool.checkedout() == 0
        with engine.connect() as connection:
            provider_checked_out_connection.append(
                connection.execute(text("SELECT 1")).scalar_one()
            )
        return {"documents": []}

    service = RecommendationImageService(search=search)
    with Session(engine) as db:
        result = service.enrich(db, 1, _recommendation())
        assert result.recommendations[0].image_origin_type == "placeholder"
    assert provider_checked_out_connection == [1]
    assert engine.pool.checkedout() == 0
    engine.dispose()
