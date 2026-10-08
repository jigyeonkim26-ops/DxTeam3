import json
from datetime import date, datetime, timezone

import pytest

from app.gemini_place_recommendation_service import GeminiPlaceRecommendationService
from app.gemini_preference_keyword_service import GeminiPreferenceKeywordService
from app.models import EmotionCode, PlaceCandidate, PreferenceKeyword, RecommendationMemory
from app.place_recommendation_service import InvalidRecommendationError
from app.place_recommendation_service import PlaceRecommendationService
from app.place_web_search_service import PlaceWebSearchService
from app.preference_keyword_service import PreferenceKeywordService
from app.tavily_place_search_service import TavilyPlaceSearchService


class FakeResponse:
    def __init__(self, body):
        self.body = body

    def raise_for_status(self):
        return None

    def json(self):
        return self.body


def memory(name="기존 장소", address="광주광역시 동구 예술길"):
    return RecommendationMemory(
        memory_id=1, user_id=1, place_id=1, place_name=name, address=address,
        latitude=35.1, longitude=126.9, content="노을을 보며 조용히 산책했다",
        emotion_code=EmotionCode.LOVE, emotion_meaning="최고", visited_on=date(2026, 1, 1),
        created_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
    )


def test_gemini_keyword_parses_caps_and_sorts_scores():
    body = {"candidates": [{"content": {"parts": [{"text": json.dumps({"keywords": [
        {"keyword": "산책", "score": 0.85}, {"keyword": "노을", "score": 0.95},
        {"keyword": "산책", "score": 0.8}, {"keyword": "조용한", "score": 0.9},
        {"keyword": "자연", "score": 0.7}, {"keyword": "카페", "score": 0.6},
    ]})}]}}]}
    result = GeminiPreferenceKeywordService(api_key="test", model="test-model", post_json=lambda *_, **__: FakeResponse(body)).extract_keywords([memory()])
    assert [item.keyword for item in result.keywords] == ["노을", "조용한", "산책", "자연", "카페"]
    assert len(result.keywords) == 5
    assert all(0 <= item.score <= 1 for item in result.keywords)


def test_tavily_queries_prioritize_high_scores_and_candidates_keep_source_and_null_coordinates():
    keywords = [PreferenceKeyword(keyword="산책", score=0.85), PreferenceKeyword(keyword="노을", score=0.95), PreferenceKeyword(keyword="조용한", score=0.9)]
    queries = TavilyPlaceSearchService.build_queries("광주광역시", keywords)
    assert queries == ["광주광역시 노을 조용한 산책 명소", "광주광역시 노을 전망 장소", "광주광역시 조용한 산책 장소"]
    body = {"results": [
        {"title": "무등산 전망대 - 광주 관광", "url": "https://example.test/mudeung", "content": "광주에서 노을과 조용한 산책을 즐길 수 있는 무등산 전망대입니다."},
        {"title": "무등산 전망대 | 안내", "url": "https://example.test/mudeung-2", "content": "노을 산책 장소 무등산 전망대"},
        {"title": "기존 장소 - 안내", "url": "https://example.test/old", "content": "노을 산책 장소"},
    ]}
    result = TavilyPlaceSearchService(api_key="test", post_json=lambda *_, **__: FakeResponse(body)).search_candidates(keywords, [memory()])
    assert len(result.candidates) == 1
    candidate = result.candidates[0]
    assert candidate.name == "무등산 전망대"
    assert candidate.source_url == "https://example.test/mudeung"
    assert candidate.latitude is None and candidate.longitude is None


def test_gemini_top_three_is_sorted_and_preserves_candidate_source_and_coordinates():
    candidates = [
        PlaceCandidate(name="A", address=None, latitude=None, longitude=None, matched_keywords=["노을"], summary="노을", source_url="https://a"),
        PlaceCandidate(name="B", address="광주", latitude=None, longitude=None, matched_keywords=["산책"], summary="산책", source_url="https://b"),
        PlaceCandidate(name="C", address=None, latitude=None, longitude=None, matched_keywords=["조용한"], summary="조용한", source_url="https://c"),
        PlaceCandidate(name="D", address=None, latitude=None, longitude=None, matched_keywords=["노을"], summary="노을", source_url="https://d"),
    ]
    assessment = {"recommendations": [
        {"name": "B", "address": "광주", "source_url": "https://b", "match_score": 0.7, "matched_keywords": ["산책"], "reason": "산책 취향에 맞습니다."},
        {"name": "A", "address": None, "source_url": "https://a", "match_score": 0.95, "matched_keywords": ["노을"], "reason": "노을 취향에 맞습니다."},
        {"name": "C", "address": None, "source_url": "https://c", "match_score": 0.8, "matched_keywords": ["조용한"], "reason": "조용한 분위기에 맞습니다."},
        {"name": "D", "address": None, "source_url": "https://d", "match_score": 0.6, "matched_keywords": ["노을"], "reason": "추가 후보입니다."},
    ]}
    body = {"candidates": [{"content": {"parts": [{"text": json.dumps(assessment)}]}}]}
    result = GeminiPlaceRecommendationService(api_key="test", model="test-model", post_json=lambda *_, **__: FakeResponse(body)).recommend(
        [memory()], [PreferenceKeyword(keyword="노을", score=0.95), PreferenceKeyword(keyword="조용한", score=0.9), PreferenceKeyword(keyword="산책", score=0.85)], candidates,
    )
    assert [item.name for item in result.recommendations] == ["A", "C", "B"]
    assert len(result.recommendations) == 3
    assert result.recommendations[0].source_url == "https://a"
    assert result.recommendations[0].latitude is None and result.recommendations[0].longitude is None


def test_gemini_rejects_a_place_not_in_candidates():
    body = {"candidates": [{"content": {"parts": [{"text": json.dumps({"recommendations": [{
        "name": "없는 장소", "address": None, "source_url": "https://missing", "match_score": 1,
        "matched_keywords": ["노을"], "reason": "검증 실패",
    }]})}]}}]}
    with pytest.raises(InvalidRecommendationError):
        GeminiPlaceRecommendationService(api_key="test", model="test-model", post_json=lambda *_, **__: FakeResponse(body)).recommend(
            [memory()], [PreferenceKeyword(keyword="노을", score=0.95)],
            [PlaceCandidate(name="실제 후보", address=None, matched_keywords=["노을"], summary="후보", source_url="https://actual")],
        )


def test_existing_openai_provider_services_remain_available():
    assert PreferenceKeywordService.API_URL == "https://api.openai.com/v1/chat/completions"
    assert PlaceWebSearchService.API_URL == "https://api.openai.com/v1/responses"
    assert PlaceRecommendationService.API_URL == "https://api.openai.com/v1/responses"
