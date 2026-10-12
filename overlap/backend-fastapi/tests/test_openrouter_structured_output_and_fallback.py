import httpx

from app.ai_recommendation_models import PlaceCandidate, PreferenceKeyword
from app.openrouter_place_recommendation_service import OpenRouterPlaceRecommendationService
from app.openrouter_preference_keyword_service import OpenRouterPreferenceKeywordService


def _keyword_record(content="산책 산책 조용한", place_name="사직공원"):
    return type("RecordInput", (), {
        "content": content,
        "emotion_code": type("Emotion", (), {"value": "good"})(),
        "emotion_meaning": "good",
        "place_name": place_name,
    })()


def test_keyword_request_uses_strict_json_schema_and_non_streaming_payload():
    captured = {}

    class Response:
        def raise_for_status(self):
            pass

        def json(self):
            return {"choices": [{"message": {"content": '{"keywords": []}'}}]}

    def post_json(*_, **kwargs):
        captured.update(kwargs["json"])
        return Response()

    service = OpenRouterPreferenceKeywordService(api_key="test", model="test", post_json=post_json)
    assert service.extract_keywords([_keyword_record()]).keywords == []
    assert captured["response_format"]["type"] == "json_schema"
    assert captured["response_format"]["json_schema"]["strict"] is True
    assert captured["provider"] == {"require_parameters": True}
    assert captured["temperature"] == 0
    assert captured["max_tokens"] == 300
    assert captured["stream"] is False


def test_keyword_provider_failure_uses_frequency_only_fallback():
    def post_json(*_, **__):
        raise httpx.ConnectError("unavailable")

    service = OpenRouterPreferenceKeywordService(api_key="test", model="test", post_json=post_json)
    result = service.extract_keywords([_keyword_record()])

    assert [item.keyword for item in result.keywords] == ["산책", "조용한"]
    assert result.keywords[0].score == 1
    assert all(item.keyword != "사직공원" for item in result.keywords)


def test_ranking_request_uses_strict_json_schema_and_non_streaming_payload():
    captured = {}

    class Response:
        def raise_for_status(self):
            pass

        def json(self):
            return {"choices": [{"message": {"content": '{"recommendations": []}'}}]}

    def post_json(*_, **kwargs):
        captured.update(kwargs["json"])
        return Response()

    record = type("RecordInput", (), {"content": "record", "emotion_meaning": "good", "place_name": "place"})()
    candidate = PlaceCandidate(kakao_place_id="12345", name="candidate", summary="summary", source_url="https://candidate")
    service = OpenRouterPlaceRecommendationService(api_key="test", model="test", post_json=post_json)
    assert service.recommend([record], [PreferenceKeyword(keyword="walk", score=1)], [candidate]).recommendations == []
    assert captured["response_format"]["type"] == "json_schema"
    assert captured["response_format"]["json_schema"]["strict"] is True
    assert captured["provider"] == {"require_parameters": True}
    assert captured["temperature"] == 0
    assert captured["max_tokens"] == 900
    assert captured["stream"] is False
