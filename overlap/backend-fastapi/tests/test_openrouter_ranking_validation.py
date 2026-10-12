import json

import pytest

from app.ai_recommendation_errors import InvalidRecommendationError
from app.ai_recommendation_models import PlaceCandidate, PreferenceKeyword
from app.openrouter_place_recommendation_service import OpenRouterPlaceRecommendationService


def _recommendation_content(source_url, matched_keywords):
    return json.dumps({"recommendations": [{
        "name": "candidate", "address": None, "source_url": source_url,
        "match_score": 0.8, "matched_keywords": matched_keywords, "reason": "reason",
    }]})


def _recommend(content):
    class Response:
        def raise_for_status(self):
            pass

        def json(self):
            return {"choices": [{"message": {"content": content}}]}

    record = type("RecordInput", (), {
        "content": "record", "emotion_meaning": "good", "place_name": "place",
    })()
    candidate = PlaceCandidate(name="candidate", summary="summary", source_url="https://candidate")
    service = OpenRouterPlaceRecommendationService(
        api_key="test", model="test", post_json=lambda *_, **__: Response(),
    )
    return service.recommend(
        [record], [PreferenceKeyword(keyword="keyword", score=1)], [candidate],
    )


@pytest.mark.parametrize("matched_keywords", [[], ["keyword"]])
def test_matched_candidate_is_returned_with_optional_matched_keywords(matched_keywords):
    result = _recommend(_recommendation_content("https://candidate", matched_keywords))

    assert len(result.recommendations) == 1
    assert result.recommendations[0].matched_keywords == matched_keywords
    assert result.recommendations[0].source_url == "https://candidate"


def test_outside_candidate_remains_rejected():
    with pytest.raises(InvalidRecommendationError):
        _recommend(_recommendation_content("https://outside", []))
