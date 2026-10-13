import pytest

from app.ai_recommendation_errors import AIResponseError
from app.ai_recommendation_models import PlaceCandidate, PreferenceKeyword
from app.openrouter_place_recommendation_service import OpenRouterPlaceRecommendationService


@pytest.mark.parametrize("content", [
    '```json\n{"recommendations": []}\n```',
    'Here is the result: {"recommendations": []} Thank you.',
    '```json\n[]\n```',
])
def test_parses_fenced_or_explained_json(content):
    assert OpenRouterPlaceRecommendationService._parse_recommendations_content(content) == []


@pytest.mark.parametrize("content", ["", "```json\n```", "not json"])
def test_invalid_content_remains_an_ai_response_error(content):
    class Response:
        def raise_for_status(self):
            pass

        def json(self):
            return {"choices": [{"message": {"content": content}}]}

    record = type("RecordInput", (), {"content": "record", "emotion_meaning": "good", "place_name": "place"})()
    candidate = PlaceCandidate(kakao_place_id="12345", name="place", summary="summary", source_url="https://place")
    with pytest.raises(AIResponseError):
        OpenRouterPlaceRecommendationService(api_key="test", model="test", post_json=lambda *_, **__: Response()).recommend(
            [record], [PreferenceKeyword(keyword="keyword", score=1)], [candidate]
        )
