import pytest
from app.openrouter_preference_keyword_service import OpenRouterPreferenceKeywordService


@pytest.mark.parametrize("content", [
    '{"keywords": [{"keyword": "walk", "score": 0.8}]}',
    '```json\n{"keywords": [{"keyword": "walk", "score": 0.8}]}\n```',
    'Here is the result: {"keywords": [{"keyword": "walk", "score": 0.8}]} Thank you.',
    '[{"keyword": "walk", "score": 0.8}]',
])
def test_parses_plain_fenced_or_explained_keyword_json(content):
    parsed = OpenRouterPreferenceKeywordService._parse_keywords_content(content)

    assert parsed["keywords"] == [{"keyword": "walk", "score": 0.8}]


@pytest.mark.parametrize("content", [
    "",
    "not json",
    '{"recommendations": []}',
    '{"keywords": "not an array"}',
])
def test_invalid_keyword_content_uses_local_fallback(content):
    class Response:
        def raise_for_status(self):
            pass

        def json(self):
            return {"choices": [{"message": {"content": content}}]}

    record = type("RecordInput", (), {
        "content": "record", "emotion_code": type("Emotion", (), {"value": "good"})(),
        "emotion_meaning": "good", "place_name": "place",
    })()
    service = OpenRouterPreferenceKeywordService(
        api_key="test", model="test", post_json=lambda *_, **__: Response(),
    )

    result = service.extract_keywords([record])

    assert [item.keyword for item in result.keywords] == ["record"]
