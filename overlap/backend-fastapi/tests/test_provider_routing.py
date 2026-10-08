import json
from datetime import date, datetime, timezone

from app.gemini_place_recommendation_service import GeminiPlaceRecommendationService
from app.gemini_preference_keyword_service import GeminiPreferenceKeywordService
from app.models import EmotionCode, PlaceCandidate, PreferenceKeyword, RecommendationMemory
from app.openrouter_place_recommendation_service import OpenRouterPlaceRecommendationService
from app.openrouter_preference_keyword_service import OpenRouterPreferenceKeywordService
from app.place_recommendation_service import PlaceRecommendationService
from app.place_web_search_service import PlaceWebSearchService
from app.preference_keyword_service import PreferenceKeywordService
from app.provider_factory import (
    build_preference_service,
    build_recommendation_service,
    build_search_service,
)
from app.tavily_place_search_service import TavilyPlaceSearchService


class FakeResponse:
    def __init__(self, body):
        self.body = body

    def raise_for_status(self):
        return None

    def json(self):
        return self.body


def memory():
    return RecommendationMemory(
        memory_id=1, user_id=1, place_id=1, place_name="사직공원", address="광주광역시 남구",
        latitude=35.14, longitude=126.91, content="노을이 예쁘고 조용해서 좋았어요",
        emotion_code=EmotionCode.LOVE, emotion_meaning="최고", visited_on=date(2026, 1, 1),
        created_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
    )


def test_provider_factory_routes_each_supported_combination():
    assert isinstance(build_preference_service("openrouter"), OpenRouterPreferenceKeywordService)
    assert isinstance(build_recommendation_service("openrouter"), OpenRouterPlaceRecommendationService)
    assert isinstance(build_search_service("tavily"), TavilyPlaceSearchService)
    assert isinstance(build_preference_service("openai"), PreferenceKeywordService)
    assert isinstance(build_recommendation_service("openai"), PlaceRecommendationService)
    assert isinstance(build_search_service("openai"), PlaceWebSearchService)
    assert isinstance(build_preference_service("gemini"), GeminiPreferenceKeywordService)
    assert isinstance(build_recommendation_service("gemini"), GeminiPlaceRecommendationService)


def test_openrouter_keyword_response_is_capped_validated_and_excludes_visited_place():
    body = {"choices": [{"message": {"content": json.dumps({"keywords": [
        {"keyword": "사직공원", "score": 0.99}, {"keyword": "노을", "score": 0.95},
        {"keyword": "조용한", "score": 0.9}, {"keyword": "산책", "score": 0.8},
        {"keyword": "자연", "score": 0.7}, {"keyword": "카페", "score": 0.6},
    ]})}}]}
    result = OpenRouterPreferenceKeywordService(
        api_key="test", model="openrouter/free", post_json=lambda *_, **__: FakeResponse(body)
    ).extract_keywords([memory()])
    assert [item.keyword for item in result.keywords] == ["노을", "조용한", "산책", "자연", "카페"]


def test_openrouter_top_three_validates_against_candidates_and_preserves_source_and_coordinates():
    candidates = [
        PlaceCandidate(name="광암교", address=None, latitude=None, longitude=None, matched_keywords=["노을"], summary="노을", source_url="https://example.test/bridge"),
        PlaceCandidate(name="광주호호수생태원", address=None, latitude=None, longitude=None, matched_keywords=["산책"], summary="산책", source_url="https://example.test/lake"),
    ]
    body = {"choices": [{"message": {"content": json.dumps({"recommendations": [
        {"name": "광주호호수생태원", "address": None, "source_url": "https://example.test/lake", "match_score": 0.8, "matched_keywords": ["산책"], "reason": "조용히 걷는 취향과 맞습니다."},
        {"name": "광암교", "address": None, "source_url": "https://example.test/bridge", "match_score": 0.95, "matched_keywords": ["노을"], "reason": "노을 선호와 잘 맞습니다."},
    ]})}}]}
    result = OpenRouterPlaceRecommendationService(
        api_key="test", model="openrouter/free", post_json=lambda *_, **__: FakeResponse(body)
    ).recommend([memory()], [PreferenceKeyword(keyword="노을", score=0.95), PreferenceKeyword(keyword="산책", score=0.8)], candidates)
    assert [item.name for item in result.recommendations] == ["광암교", "광주호호수생태원"]
    assert result.recommendations[0].source_url == "https://example.test/bridge"
    assert result.recommendations[0].latitude is None and result.recommendations[0].longitude is None
