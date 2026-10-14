from datetime import date

from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from app.ai_recommendation_models import PlaceRecommendationResponse
from app import ai_recommendations
from app.ai_recommendations import _log_place_decision, _records_fingerprint
from app.db import Base, get_db
from app.db_models import User
from app.main import create_app
from app.place_candidate_search_service import (
    CandidateSearchResult,
    CategoryMatchStatus,
    FeatureEvidenceStatus,
    KakaoPlaceCandidate,
    PlaceCandidateEvidence,
    PlaceCategoryClassification,
    PreferenceEvidence,
    ProviderStatus,
    PlaceCandidateSearchService,
)
from app.record_models import Place, Record
from app.record_preference_analysis import (
    EvidenceStatus,
    FacetTargetKind,
    PlaceType,
    PreferenceFacet,
    RecordPreferenceAnalysis,
    RecordPreferenceAnalysisResponse,
    RecommendationCategory,
    RecordPreferenceAnalysisService,
)
from app.recommendation_record_adapter import RecordRecommendationAdapter
from app.recommendation_record_adapter import RecommendationEmotionCode, RecommendationRecord
from app.security import hash_password


class Analysis:
    def analyze(self, records, *, category):
        assert category == RecommendationCategory.ALL
        return RecordPreferenceAnalysisResponse(analyses=[RecordPreferenceAnalysis(
            record_id=1,
            place_name="이자카야",
            place_type=PlaceType.BAR,
            place_type_label="이자카야",
            categories=[RecommendationCategory.BAR, RecommendationCategory.FOOD],
            emotion="LOVE",
            emotion_intensity=1.0,
            evidence_status=EvidenceStatus.VERIFIED,
            facets=[PreferenceFacet(
                target_kind=FacetTargetKind.DRINK,
                target_text="유자하이볼",
                features=["맛"],
                categories=[RecommendationCategory.BAR],
                polarity="liked",
                evidence="유자하이볼이 맛있었다",
                confidence=0.95,
            )],
        )])


class CandidateSearch:
    def __init__(self, category_status=CategoryMatchStatus.CONFIRMED):
        self.category_status = category_status
        self.calls = []

    def search(self, **kwargs):
        self.calls.append(kwargs)
        place = KakaoPlaceCandidate(
            kakao_place_id="987654",
            place_name="유자 이자카야",
            address="광주광역시 동구",
            latitude=35.15,
            longitude=126.92,
            category_group_code="FD6",
            category_name="음식점 > 술집 > 이자카야",
            place_url="https://place.map.kakao.com/987654",
        )
        candidate = PlaceCandidateEvidence(
            place=place,
            classification=PlaceCategoryClassification(
                requested_category=RecommendationCategory.BAR,
                categories=[RecommendationCategory.BAR, RecommendationCategory.FOOD],
                status=self.category_status,
                evidence=["kakao_category_name:bar_subcategory"],
            ),
            preference_evidence=[PreferenceEvidence(
                record_id=1,
                preference="유자하이볼",
                status=FeatureEvidenceStatus.CONFIRMED,
                evidence_text="메뉴에 유자 하이볼이 기재되어 있습니다.",
                evidence_url="https://example.test/menu",
            )],
            feature_search_status=FeatureEvidenceStatus.CONFIRMED,
        )
        return CandidateSearchResult(
            category=kwargs["category"],
            region=kwargs["region"],
            kakao_status=ProviderStatus.COMPLETE,
            tavily_status=ProviderStatus.COMPLETE,
            kakao_call_count=1,
            tavily_call_count=1,
            candidates=[candidate],
        )


class NoImages:
    def enrich(self, db, user_id, response):
        return response


def _client(candidate_search=None, *, inject_services=True, preference_analysis=None):
    engine = create_engine("sqlite://", poolclass=StaticPool, connect_args={"check_same_thread": False})
    Base.metadata.create_all(engine)
    with Session(engine) as db:
        db.add(User(id=1, email="user@example.test", nickname="user", gender="female", birth_date=date(1990, 1, 1), password_hash=hash_password("password-123")))
        db.add(Place(id=1, provider="kakao", external_place_id="111", name="이자카야", address="광주광역시 동구", road_address=None, latitude=35.1, longitude=126.9))
        db.add(Record(id=1, author_id=1, place_id=1, content="유자하이볼이 맛있었다", emotion="excellent", is_private=True))
        db.commit()
    app_options = dict(
        use_db_auth=True,
        recommendation_adapter=RecordRecommendationAdapter(),
        recommendation_image_service=NoImages(),
    )
    if inject_services:
        app_options.update(
            candidate_search_service=candidate_search,
            preference_analysis_service=preference_analysis or Analysis(),
        )
    api = create_app(**app_options)

    def session():
        with Session(engine) as db:
            yield db

    api.dependency_overrides[get_db] = session
    client = TestClient(api)
    token = client.post("/auth/login", json={"email": "user@example.test", "password": "password-123"}).json()["access_token"]
    return client, engine, {"Authorization": "Bearer " + token}


def test_category_api_integrates_analysis_kakao_candidates_and_tavily_evidence():
    search = CandidateSearch()
    client, engine, headers = _client(search)
    try:
        response = client.get("/ai/recommendations?category=bar&region=%EA%B4%91%EC%A3%BC", headers=headers)
        assert response.status_code == 200, response.text
        payload = response.json()["recommendations"]
        assert len(payload) == 1
        assert payload[0]["kakao_place_id"] == "987654"
        assert payload[0]["matched_keywords"] == ["유자하이볼"]
        assert payload[0]["matched_keywords"]
        assert "Tavily" not in payload[0]["reason"]
        assert "Kakao" not in payload[0]["reason"]
        assert search.calls[0]["category"] == RecommendationCategory.BAR
        assert search.calls[0]["region"] == "광주"
        assert search.calls[0]["preferences"][0].facets[0].target_text == "유자하이볼"
    finally:
        client.close()
        engine.dispose()


def test_category_api_does_not_return_uncertain_place_classification():
    search = CandidateSearch(CategoryMatchStatus.VERIFICATION_REQUIRED)
    client, engine, headers = _client(search)
    try:
        response = client.get("/ai/recommendations?category=bar&region=%EA%B4%91%EC%A3%BC", headers=headers)
        assert response.status_code == 200, response.text
        assert response.json()["recommendations"] == []
    finally:
        client.close()
        engine.dispose()


def test_recommendation_response_model_remains_backward_compatible():
    assert PlaceRecommendationResponse().model_dump() == {"recommendations": []}


def test_analysis_fingerprint_isolated_by_user_record_identity():
    def record(user_id):
        return RecommendationRecord(
            record_id=1, user_id=user_id, place_id=1, kakao_place_id=None,
            place_name="Synthetic cafe", address="Gwangju", content="quiet",
            emotion_code=RecommendationEmotionCode.LOVE, emotion_meaning="positive",
        )

    assert _records_fingerprint([record(1)]) != _records_fingerprint([record(2)])


def test_analysis_provider_failure_without_any_safe_search_input_returns_service_error():
    class FailedAnalysis:
        def analyze(self, records, *, category):
            return RecordPreferenceAnalysisResponse(analyses=[RecordPreferenceAnalysis(
                record_id=1, place_name="라운지", place_type=PlaceType.UNKNOWN,
                categories=[], emotion="LOVE", emotion_intensity=1.0,
                facets=[], evidence_status=EvidenceStatus.UNAVAILABLE,
            )])

    class NoSearchInput:
        def search(self, **kwargs):
            return CandidateSearchResult(
                category=kwargs["category"], region=kwargs["region"],
                kakao_status=ProviderStatus.NO_RESULTS, tavily_status=ProviderStatus.NO_RESULTS,
                kakao_call_count=0, tavily_call_count=0, candidates=[], query_count=0,
                search_skip_reason="no_supported_preference_query",
            )

    client, engine, headers = _client(NoSearchInput(), preference_analysis=FailedAnalysis())
    try:
        response = client.get("/ai/recommendations?category=all&region=%EA%B4%91%EC%A3%BC", headers=headers)
        assert response.status_code == 503
    finally:
        client.close()
        engine.dispose()


def test_unavailable_analysis_is_not_cached_and_is_retried_on_next_empty_session_request():
    calls = []

    class IntermittentAnalysis(Analysis):
        def analyze(self, records, *, category):
            calls.append(category)
            result = super().analyze(records, category=category)
            if len(calls) == 1:
                return result.model_copy(update={
                    "analyses": [item.model_copy(update={"evidence_status": EvidenceStatus.UNAVAILABLE})
                                 for item in result.analyses]
                })
            return result

    client, engine, headers = _client(
        CandidateSearch(), preference_analysis=IntermittentAnalysis(),
    )
    try:
        first = client.get("/ai/recommendations?category=bar&region=%EA%B4%91%EC%A3%BC", headers=headers)
        # Change region to bypass the region-scoped recommendation session
        # while retaining the same user and record fingerprint.
        second = client.get("/ai/recommendations?category=bar&region=%EB%8C%80%EA%B5%AC", headers=headers)
        assert first.status_code == second.status_code == 200
        assert calls == [RecommendationCategory.ALL, RecommendationCategory.ALL]
    finally:
        client.close()
        engine.dispose()


def test_candidate_decision_diagnostic_formats_reason_without_logging_error(caplog):
    import logging

    with caplog.at_level(logging.INFO, logger="uvicorn.error"):
        _log_place_decision(
            pipeline="category-v3", stage="test", kakao_place_id="synthetic-1",
            place_name="Synthetic Place", category_name="Restaurant > Izakaya",
            category_group_code="FD6", category_status="confirmed",
            decision="accepted", reason="category_confirmed",
        )

    assert "reason=category_confirmed" in caplog.text


def test_default_create_app_uses_category_pipeline_for_every_category_and_cache(monkeypatch):
    analysis_calls = []
    search_calls = []
    log_messages = []
    original_analyze = Analysis.analyze
    original_search = CandidateSearch.search

    def analyze(self, records, *, category):
        analysis_calls.append(category)
        return original_analyze(self, records, category=category)

    def search(self, **kwargs):
        search_calls.append(kwargs["category"])
        return original_search(CandidateSearch(), **kwargs)

    monkeypatch.setattr(RecordPreferenceAnalysisService, "analyze", analyze)
    monkeypatch.setattr(PlaceCandidateSearchService, "search", search)
    monkeypatch.setattr(ai_recommendations.logger, "info", lambda message, *args: log_messages.append((message, args)))
    client, engine, headers = _client(inject_services=False)
    try:
        # Missing category must take the default `all` v3 branch. Then every
        # supported category is passed through to the same injected default service.
        for query, expected in [
            ("", RecommendationCategory.ALL),
            ("?category=all", RecommendationCategory.ALL),
            ("?category=food", RecommendationCategory.FOOD),
            ("?category=bar", RecommendationCategory.BAR),
            ("?category=cafe", RecommendationCategory.CAFE),
            ("?category=nature", RecommendationCategory.NATURE),
            ("?category=activity", RecommendationCategory.ACTIVITY),
        ]:
            response = client.get("/ai/recommendations" + query, headers=headers)
            assert response.status_code == 200, response.text
            assert search_calls[-1] == expected
        # First request analyzed once; other categories reuse that analysis.
        assert analysis_calls == [RecommendationCategory.ALL]
        assert search_calls == [
            RecommendationCategory.ALL,
            RecommendationCategory.FOOD,
            RecommendationCategory.BAR,
            RecommendationCategory.CAFE,
            RecommendationCategory.NATURE,
            RecommendationCategory.ACTIVITY,
        ]
        # The all session is cached and refresh preserves the response contract.
        before = len(search_calls)
        cached = client.get("/ai/recommendations?refresh=true", headers=headers)
        assert cached.status_code == 200
        assert len(search_calls) == before
        assert any("pipeline=%s" in message and "category=%s" in message and "category-v3" in args and "all" in args for message, args in log_messages)
        assert not any("legacy-tavily-v2" in args for _, args in log_messages)
    finally:
        client.close()
        engine.dispose()
