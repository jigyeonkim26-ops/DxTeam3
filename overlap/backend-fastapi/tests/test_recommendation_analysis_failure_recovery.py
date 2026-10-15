import httpx

from app.ai_recommendations import _build_category_recommendations
from app.place_candidate_search_service import (
    CategoryMatchStatus,
    KakaoPlaceCandidate,
    PlaceCandidateEvidence,
    PlaceCandidateSearchService,
    PlaceCategoryClassification,
    ProviderStatus,
)
from app.record_preference_analysis import (
    RecordPreferenceAnalysisService,
    RecommendationCategory,
)
from app.recommendation_record_adapter import RecommendationEmotionCode, RecommendationRecord


def _records():
    nature = [
        RecommendationRecord(
            record_id=i, user_id=1, place_id=i, kakao_place_id=None,
            place_name=f"광주 공원 {i}", address="광주광역시 동구",
            content="산책길 풍경이 좋았다.", emotion_code=RecommendationEmotionCode.LOVE,
            emotion_meaning="positive",
        ) for i in range(1, 8)
    ]
    unknown = [
        RecommendationRecord(
            record_id=i, user_id=1, place_id=i, kakao_place_id=None,
            place_name=f"모호한 장소 {i}", address="광주광역시 동구",
            content=("유자하이볼이랑 꼬치가 맛있었다." if i == 8 else "넓어서 좋았다."),
            emotion_code=RecommendationEmotionCode.LIKE,
            emotion_meaning="positive",
        ) for i in range(8, 14)
    ]
    return nature + unknown


def _fail_openrouter(*args, **kwargs):
    request = httpx.Request("POST", "https://openrouter.ai/api/v1/chat/completions")
    response = httpx.Response(429, request=request)
    raise httpx.HTTPStatusError("synthetic rate limit", request=request, response=response)


def _kakao_place():
    return {
        "id": "731001", "place_name": "광주 확인된 공원",
        "road_address_name": "광주광역시 동구 무등로", "address_name": "광주광역시 동구 무등로",
        "x": "126.92", "y": "35.15", "category_group_code": "AT4",
        "category_name": "여행 > 공원", "place_url": "https://place.map.kakao.com/731001",
    }


def test_thirteen_record_analysis_failure_still_searches_all_and_nature_and_ranks_type_match():
    records = _records()
    analyzer = RecordPreferenceAnalysisService(
        api_key="test-token", model="test-model", post_json=_fail_openrouter,
    )
    kakao_queries = []

    def kakao(query, **kwargs):
        kakao_queries.append(query)
        return [_kakao_place()]

    search = PlaceCandidateSearchService(
        kakao_search=kakao, kakao_api_key="test-kakao", tavily_api_key="",
    )
    for selected_category in (RecommendationCategory.ALL, RecommendationCategory.NATURE):
        analyses = analyzer.analyze(records, category=selected_category)
        result = search.search(
            category=selected_category, region="광주광역시", preferences=analyses.analyses,
        )
        assert result.query_count > 0
        assert result.kakao_call_count + result.kakao_cache_hit_count > 0
        assert result.candidates
        recommendations = _build_category_recommendations(result, analyses, selected_category)
        assert recommendations
        assert recommendations[0].match_score <= 0.45
        assert "산책" in recommendations[0].matched_keywords
        assert "공원" in recommendations[0].reason

    assert any("산책로" in query for query in kakao_queries)
    assert any("유자하이볼" in query for query in kakao_queries)
