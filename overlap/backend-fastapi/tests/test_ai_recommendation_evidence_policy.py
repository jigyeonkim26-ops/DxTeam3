from app.ai_recommendations import _build_category_recommendations
from app.place_candidate_search_service import (
    CandidateSearchResult,
    CategoryMatchStatus,
    FeatureEvidenceStatus,
    KakaoCategoryClassifier,
    KakaoPlaceCandidate,
    PlaceCandidateEvidence,
    ProviderStatus,
    PlaceCandidateSearchService,
    _region_key,
    _search_region,
)
from app.record_preference_analysis import (
    EvidenceStatus,
    FacetTargetKind,
    PlaceType,
    PreferenceFacet,
    RecommendationCategory,
    RecordPreferenceAnalysis,
    RecordPreferenceAnalysisResponse,
    RecordPreferenceAnalysisService,
)
from app.recommendation_record_adapter import RecommendationEmotionCode, RecommendationRecord
from datetime import date
from sqlalchemy import create_engine
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool
from app.db import Base
from app.db_models import User
from app.record_models import Place, Record
from app.security import hash_password
from app.recommendation_record_adapter import RecordRecommendationAdapter


def _analysis(target="산책", *, category=RecommendationCategory.NATURE, kind=FacetTargetKind.ACTIVITY):
    return RecordPreferenceAnalysis(
        record_id=1,
        place_name="무등산",
        place_type=PlaceType.NATURE if category == RecommendationCategory.NATURE else PlaceType.FOOD,
        categories=[category],
        emotion=RecommendationEmotionCode.LOVE,
        emotion_intensity=0.95,
        evidence_status=EvidenceStatus.VERIFIED,
        facets=[PreferenceFacet(
            target_kind=kind,
            target_text=target,
            features=[],
            categories=[category],
            polarity="liked",
            evidence=f"{target}이 좋았다.",
            confidence=0.9,
        )],
    )


def _place(place_id, name, address, category_name, code="AT4"):
    return KakaoPlaceCandidate(
        kakao_place_id=str(place_id), place_name=name, address=address,
        latitude=35.15, longitude=126.92, category_group_code=code,
        category_name=category_name,
        place_url=f"https://place.map.kakao.com/{place_id}",
    )


def test_merged_gwangju_aliases_match_city_but_keep_district_scope():
    assert _search_region("전남광주통합특별시 서구") == "광주 서구"
    assert _region_key("전남광주통합특별시") == _region_key("광주광역시")
    assert not PlaceCandidateSearchService._same_region("광주광역시 북구 용봉동", "전남광주통합특별시 서구")
    assert PlaceCandidateSearchService._same_region("광주광역시 북구 용봉동", "광주")


def test_nature_classifier_accepts_trail_park_arboretum_and_rejects_shop():
    for index, kind in enumerate(("공원", "산책로", "수목원", "등산로", "자연관광지"), 1):
        place = _place(index, f"광주 {kind}", "광주광역시 북구", f"여행 > 관광,명소 > {kind}")
        assert KakaoCategoryClassifier.classify(place, RecommendationCategory.NATURE).status == CategoryMatchStatus.CONFIRMED
    shop = _place(20, "숲길카페", "광주광역시 북구", "음식점 > 카페 > 커피전문점", "CE7")
    assert KakaoCategoryClassifier.classify(shop, RecommendationCategory.NATURE).status == CategoryMatchStatus.MISMATCH


def test_inferred_narrow_region_expands_to_city_after_district_candidates_mismatch():
    calls = []

    def kakao(query, **kwargs):
        calls.append(query)
        if "서구" in query:
            return [
                {"id": str(100 + index), "place_name": f"북구 산책로 {index}",
                 "road_address_name": "광주광역시 북구 용봉동", "x": "126.9", "y": "35.2",
                 "category_group_code": "AT4", "category_name": "여행 > 관광,명소 > 산책로",
                 "place_url": f"https://place.map.kakao.com/{100 + index}"}
                for index in range(3)
            ]
        return [{
            "id": "900", "place_name": "광주 북구 산책로", "road_address_name": "광주광역시 북구 용봉동",
            "x": "126.9", "y": "35.2", "category_group_code": "AT4",
            "category_name": "여행 > 관광,명소 > 산책로",
            "place_url": "https://place.map.kakao.com/900",
        }]

    result = PlaceCandidateSearchService(
        kakao_search=kakao, kakao_api_key="mock", tavily_api_key="",
    ).search(
        category=RecommendationCategory.ALL,
        region="전남광주통합특별시 서구",
        preferences=[_analysis()],
        allow_region_expansion=True,
    )
    assert any(query.startswith("광주 ") and "서구" not in query for query in calls)
    assert result.kakao_call_count <= 12
    assert [item.place.kakao_place_id for item in result.candidates] == ["900"]


def test_twelve_nature_records_recover_real_north_gwangju_trail_after_district_mismatch():
    records = [
        RecommendationRecord(
            record_id=index, user_id=1, place_id=index, kakao_place_id=None,
            place_name="무등산", address="전남광주통합특별시 서구",
            content="무등산 산책길의 자연 풍경이 좋았다.",
            emotion_code=RecommendationEmotionCode.LOVE, emotion_meaning="좋아",
        )
        for index in range(1, 13)
    ]
    records.append(RecommendationRecord(
        record_id=13, user_id=1, place_id=13, kakao_place_id=None,
        place_name="광주 농구장", address="전남광주통합특별시 서구",
        content="농구 경기가 즐거웠다.",
        emotion_code=RecommendationEmotionCode.LIKE, emotion_meaning="좋아",
    ))
    preferences = RecordPreferenceAnalysisService(api_key="", model="").analyze(records).analyses
    assert sum(RecommendationCategory.NATURE in row.categories for row in preferences) == 12
    assert sum(bool(row.facets) for row in preferences[:12]) == 12

    calls = []

    def kakao(query, **kwargs):
        calls.append(query)
        if "서구" in query:
            return [
                {"id": str(1000 + index), "place_name": f"다른 구 산책로 {index}",
                 "road_address_name": "광주광역시 북구 용봉동", "x": "126.9", "y": "35.2",
                 "category_group_code": "AT4", "category_name": "여행 > 관광,명소 > 산책로",
                 "place_url": f"https://place.map.kakao.com/{1000 + index}"}
                for index in range(3)
            ]
        return [{
            "id": "901", "place_name": "용봉동 산책로", "road_address_name": "광주광역시 북구 용봉동",
            "x": "126.9", "y": "35.2", "category_group_code": "AT4",
            "category_name": "여행 > 관광,명소 > 산책로",
            "place_url": "https://place.map.kakao.com/901",
        }]

    service = PlaceCandidateSearchService(kakao_search=kakao, kakao_api_key="mock", tavily_api_key="")
    region = "전남광주통합특별시 서구"
    search = service.search(
        category=RecommendationCategory.ALL, region=region, preferences=preferences,
        allow_region_expansion=True,
    )
    assert search.candidates
    assert search.kakao_call_count <= 12
    assert search.candidates[0].classification.status == CategoryMatchStatus.CONFIRMED
    assert any(query.startswith("광주 ") and "서구" not in query for query in calls)
    recommendations = _build_category_recommendations(
        search, RecordPreferenceAnalysisResponse(analyses=preferences), RecommendationCategory.ALL,
    )
    assert 1 <= len(recommendations) <= 3
    assert "산책" in recommendations[0].matched_keywords
    assert recommendations[0].name == "용봉동 산책로"


def test_nature_type_is_a_limited_personalized_match_without_claiming_details():
    place = _place(31, "북구 산책로", "광주광역시 북구", "여행 > 관광,명소 > 산책로")
    classification = KakaoCategoryClassifier.classify(place, RecommendationCategory.ALL)
    result = CandidateSearchResult(
        category=RecommendationCategory.ALL, region="광주", kakao_status=ProviderStatus.COMPLETE,
        tavily_status=ProviderStatus.NO_RESULTS, kakao_call_count=1, tavily_call_count=0,
        candidates=[PlaceCandidateEvidence(
            place=place, classification=classification, feature_search_status=FeatureEvidenceStatus.UNAVAILABLE,
        )],
    )
    recommendations = _build_category_recommendations(
        result, RecordPreferenceAnalysisResponse(analyses=[_analysis()]), RecommendationCategory.ALL,
    )
    assert len(recommendations) == 1
    assert recommendations[0].matched_keywords == ["산책"]
    assert "산책" in recommendations[0].reason
    assert "전망" not in recommendations[0].reason


def test_food_category_only_candidate_is_excluded_without_verified_menu_evidence():
    place = _place(41, "미송식당", "광주광역시 서구", "음식점 > 한식", "FD6")
    classification = KakaoCategoryClassifier.classify(place, RecommendationCategory.ALL)
    result = CandidateSearchResult(
        category=RecommendationCategory.ALL, region="광주", kakao_status=ProviderStatus.COMPLETE,
        tavily_status=ProviderStatus.UNAVAILABLE, kakao_call_count=1, tavily_call_count=0,
        candidates=[PlaceCandidateEvidence(
            place=place, classification=classification, feature_search_status=FeatureEvidenceStatus.INSUFFICIENT,
        )],
    )
    recommendations = _build_category_recommendations(
        result,
        RecordPreferenceAnalysisResponse(analyses=[_analysis(
            "낙지볶음", category=RecommendationCategory.FOOD, kind=FacetTargetKind.FOOD,
        )]),
        RecommendationCategory.ALL,
    )
    assert recommendations == []


def test_ambiguous_place_name_does_not_establish_nature_type():
    record = RecommendationRecord(
        record_id=51, user_id=1, place_id=1, place_name="산등무", content="조용해서 좋았다.",
        emotion_code=RecommendationEmotionCode.LOVE, emotion_meaning="좋아",
    )
    result = RecordPreferenceAnalysisService._base_analysis(record, None)
    assert result.place_type == PlaceType.UNKNOWN


def test_place_name_echo_alone_does_not_validate_provider_place_type():
    record = RecommendationRecord(
        record_id=52, user_id=1, place_id=1, place_name="산등무", content="조용해서 좋았다.",
        emotion_code=RecommendationEmotionCode.LOVE, emotion_meaning="좋아",
    )
    guessed = RecordPreferenceAnalysis(
        record_id=52, place_name="산등무", place_type=PlaceType.NATURE,
        place_type_label="산", place_type_evidence="산등무",
        categories=[RecommendationCategory.NATURE], emotion=RecommendationEmotionCode.LOVE,
        emotion_intensity=0.9,
    )
    result = RecordPreferenceAnalysisService._validate_evidence(guessed, record, None)
    assert result.place_type == PlaceType.UNKNOWN
    assert result.categories == []


def test_visited_place_lookup_includes_all_emotions_and_only_owner_records():
    engine = create_engine("sqlite://", poolclass=StaticPool)
    Base.metadata.create_all(engine)
    try:
        with Session(engine) as db:
            db.add_all([
                User(id=1, email="one@example.test", nickname="one", gender="female",
                     birth_date=date(1990, 1, 1), password_hash=hash_password("test-password-1")),
                User(id=2, email="two@example.test", nickname="two", gender="female",
                     birth_date=date(1990, 1, 1), password_hash=hash_password("test-password-2")),
                Place(id=1, provider="kakao", external_place_id="801", name="다녀온 장소",
                      address="광주광역시 북구", latitude=35.2, longitude=126.9),
                Place(id=2, provider="kakao", external_place_id="802", name="타인 장소",
                      address="광주광역시 서구", latitude=35.1, longitude=126.8),
                Place(id=3, provider="manual", external_place_id=None, name="직접 저장한 장소",
                      address="광주광역시 북구", latitude=35.2, longitude=126.9),
                Record(author_id=1, place_id=1, content="그저 그랬다", emotion="neutral", is_private=True),
                Record(author_id=1, place_id=3, content="직접 기록", emotion="disappointed", is_private=True),
                Record(author_id=2, place_id=2, content="좋았다", emotion="excellent", is_private=True),
            ])
            db.commit()
            ids, names = RecordRecommendationAdapter().list_visited_places(db, 1)
        assert ids == {"801"}
        assert names == {"직접 저장한 장소"}
    finally:
        engine.dispose()
