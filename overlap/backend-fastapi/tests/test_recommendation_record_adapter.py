from datetime import datetime
from types import SimpleNamespace

from app.recommendation_record_adapter import (
    RecommendationEmotionCode,
    RecordRecommendationAdapter,
)


def record(record_id, user_id, emotion, place_id=1, content="기록"):
    return SimpleNamespace(
        id=record_id,
        author_id=user_id,
        emotion=emotion,
        place_id=place_id,
        content=content,
        created_at=datetime(2026, 10, 8, 12, 0, 0),
    )


def place(name="사직공원", latitude=35.14, longitude=126.91):
    return SimpleNamespace(
        name=name,
        address="광주광역시 남구",
        road_address=None,
        latitude=latitude,
        longitude=longitude,
    )


def test_positive_emotions_map_to_recommendation_codes_and_keep_place_content():
    adapter = RecordRecommendationAdapter()
    expected = {
        "excellent": RecommendationEmotionCode.LOVE,
        "good": RecommendationEmotionCode.LIKE,
        "okay": RecommendationEmotionCode.GOOD,
    }
    for emotion, code in expected.items():
        result = adapter.to_recommendation_record(
            record(1, 7, emotion, content="노을이 예쁘고 조용해서 좋았어요"), place()
        )
        assert result.emotion_code == code
        assert result.content == "노을이 예쁘고 조용해서 좋았어요"
        assert result.place_name == "사직공원"
        assert result.visited_on is None


def test_non_positive_emotion_mapping_is_available_but_not_positive():
    adapter = RecordRecommendationAdapter()
    for emotion, code in {
        "neutral": RecommendationEmotionCode.NEUTRAL,
        "disappointed": RecommendationEmotionCode.DISAPPOINTED,
        "poor": RecommendationEmotionCode.BAD,
    }.items():
        assert adapter.to_recommendation_record(record(1, 7, emotion), place()).emotion_code == code
        assert emotion not in adapter.POSITIVE_EMOTIONS


def test_missing_place_and_coordinates_are_never_invented():
    adapter = RecordRecommendationAdapter()
    missing = adapter.to_recommendation_record(record(1, 7, "excellent", place_id=999), None)
    assert missing.place_name is None
    assert missing.address is None
    assert missing.latitude is None and missing.longitude is None
    no_coordinates = adapter.to_recommendation_record(record(2, 7, "good"), place(latitude=None, longitude=None))
    assert no_coordinates.latitude is None and no_coordinates.longitude is None
