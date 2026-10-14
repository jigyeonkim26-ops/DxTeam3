import json

import httpx
import pytest

from app.record_preference_analysis import (
    EvidenceStatus,
    PlaceType,
    RecommendationCategory,
    RecordPlaceMetadata,
    RecordPreferenceAnalysisService,
)
from app.recommendation_record_adapter import RecommendationEmotionCode, RecommendationRecord


def make_record(record_id, place_name, content, emotion=RecommendationEmotionCode.LOVE):
    return RecommendationRecord(
        record_id=record_id,
        user_id=19,
        place_id=record_id,
        kakao_place_id=None,
        place_name=place_name,
        address="광주광역시 동구",
        content=content,
        emotion_code=emotion,
        emotion_meaning=emotion.value,
    )


def facet(target_kind, target_text, features, categories, evidence, polarity="liked"):
    return {
        "target_kind": target_kind,
        "target_text": target_text,
        "features": features,
        "categories": categories,
        "polarity": polarity,
        "evidence": evidence,
        "confidence": 0.9,
    }


def response_for(records):
    class Response:
        def raise_for_status(self):
            pass

        def json(self):
            return {"choices": [{"message": {"content": json.dumps({"records": records}, ensure_ascii=False)}}]}

    return Response()


def service_for(records, captured=None):
    def post_json(*_, **kwargs):
        if captured is not None:
            captured.update(kwargs["json"])
        return response_for(records)

    return RecordPreferenceAnalysisService(api_key="test-key", model="test-model", post_json=post_json)


def test_izakaya_extracts_drink_and_food_individually_and_keeps_bar_context():
    record = make_record(1, "유자 이자카야", "유자하이볼이랑 꼬치가 정말 맛있었다.")
    service = service_for([{
        "record_id": 1, "place_type": "bar", "place_type_label": "이자카야",
        "place_type_evidence": "이자카야", "categories": ["bar", "food"],
        "facets": [
            facet("drink", "유자하이볼", ["맛있었다"], ["bar"], "유자하이볼이랑 꼬치가 정말 맛있었다."),
            facet("food", "꼬치", ["맛있었다"], ["bar", "food"], "유자하이볼이랑 꼬치가 정말 맛있었다."),
        ],
    }])
    result = service.analyze([record]).analyses[0]

    assert result.place_type == PlaceType.BAR
    assert {f.target_text for f in result.facets} == {"유자하이볼", "꼬치"}
    assert all(RecommendationCategory.BAR in f.categories for f in result.facets)


def test_cafe_quiet_and_spacious_aspects_keep_cafe_context():
    record = make_record(2, "카페 온도", "매장이 넓고 조용해서 좋았다.", RecommendationEmotionCode.LIKE)
    result = service_for([{
        "record_id": 2, "place_type": "cafe", "place_type_label": "카페",
        "place_type_evidence": "카페", "categories": ["cafe"],
        "facets": [facet("space", "매장", ["넓고", "조용해서"], ["cafe"], "매장이 넓고 조용해서 좋았다.")],
    }]).analyze([record]).analyses[0]

    assert result.place_type == PlaceType.CAFE
    assert result.facets[0].target_text == "매장"
    assert result.facets[0].features == ["넓고", "조용해서"]
    assert result.facets[0].categories == [RecommendationCategory.CAFE]


def test_spacious_alone_does_not_invent_parking_preference():
    record = make_record(3, "카페 온도", "매장이 넓어서 좋았다.")
    service = service_for([{
        "record_id": 3, "place_type": "cafe", "place_type_label": "카페",
        "place_type_evidence": "카페", "categories": ["cafe"],
            "facets": [facet("facility", "주차장", ["넓어서"], ["cafe"], "매장이 넓어서 좋았다.")],
    }])
    result = service.analyze([record]).analyses[0]

    assert result.facets == []
    assert result.evidence_status == EvidenceStatus.PARTIAL


def test_baseball_record_is_sports_activity_with_evidence_backed_facet():
    record = make_record(4, "광주 야구장", "응원하는 분위기가 정말 좋았다.")
    result = service_for([{
        "record_id": 4, "place_type": "activity", "place_type_label": "야구장",
        "place_type_evidence": "야구장", "categories": ["activity"],
        "facets": [facet("ambience", "분위기", ["응원하는"], ["activity"], "응원하는 분위기가 정말 좋았다.")],
    }]).analyze([record]).analyses[0]

    assert result.place_type == PlaceType.ACTIVITY
    assert result.categories == [RecommendationCategory.ACTIVITY]
    assert result.facets[0].target_text == "분위기"


def test_nature_record_is_nature_category():
    record = make_record(5, "무등산 자연공원", "자연 풍경이 아름다웠다.")
    result = service_for([{
        "record_id": 5, "place_type": "nature", "place_type_label": "자연공원",
        "place_type_evidence": "자연공원", "categories": ["nature"],
        "facets": [facet("scenery", "풍경", ["아름다웠다"], ["nature"], "자연 풍경이 아름다웠다.")],
    }]).analyze([record]).analyses[0]

    assert result.place_type == PlaceType.NATURE
    assert result.categories == [RecommendationCategory.NATURE]


def test_mixed_records_preserve_domain_and_category_filter_does_not_cross_transfer():
    records = [
        make_record(6, "카페 온도", "매장이 조용해서 좋았다."),
        make_record(7, "유자 이자카야", "유자하이볼이 맛있었다."),
    ]
    outputs = [
        {"record_id": 6, "place_type": "cafe", "place_type_label": "카페", "place_type_evidence": "카페", "categories": ["cafe"],
         "facets": [facet("ambience", "매장", ["조용해서"], ["cafe"], "매장이 조용해서 좋았다.")]},
        {"record_id": 7, "place_type": "bar", "place_type_label": "이자카야", "place_type_evidence": "이자카야", "categories": ["bar", "food"],
         "facets": [facet("drink", "유자하이볼", ["맛있었다"], ["bar"], "유자하이볼이 맛있었다.")]},
    ]
    service = service_for(outputs)

    cafes = service.analyze(records, category="cafe").analyses
    bars = service.analyze(records, category="bar").analyses
    all_records = service.analyze(records, category="all").analyses

    assert [x.record_id for x in cafes] == [6]
    assert [x.record_id for x in bars] == [7]
    assert [x.record_id for x in all_records] == [6, 7]


@pytest.mark.parametrize("emotion,intensity,polarity,expected_count", [
    (RecommendationEmotionCode.LOVE, 1.0, "liked", 1),
    (RecommendationEmotionCode.LIKE, 0.8, "liked", 1),
    (RecommendationEmotionCode.GOOD, 0.6, "liked", 1),
    (RecommendationEmotionCode.NEUTRAL, 0.35, "neutral", 1),
    (RecommendationEmotionCode.DISAPPOINTED, 0.2, "disliked", 1),
    (RecommendationEmotionCode.BAD, 0.0, "disliked", 1),
])
def test_emotion_strength_and_nonpositive_polarity_are_preserved(emotion, intensity, polarity, expected_count):
    record = make_record(8, "치킨 음식점", "치킨이 별로였다." if polarity == "disliked" else "치킨이 맛있었다.", emotion)
    evidence = "치킨이 별로였다." if polarity == "disliked" else "치킨이 맛있었다."
    output = {"record_id": 8, "place_type": "food", "place_type_label": "음식점", "place_type_evidence": "음식점", "categories": ["food"],
              "facets": [facet("menu", "치킨", ["별로였다" if polarity == "disliked" else "맛있었다"], ["food"], evidence, polarity)]}
    result = service_for([output]).analyze([record]).analyses[0]

    assert result.emotion_intensity == intensity
    assert len(result.facets) == expected_count
    assert result.facets[0].polarity == polarity


def test_model_cannot_add_menu_not_in_source_text():
    record = make_record(9, "치킨 음식점", "치킨이 맛있었다.")
    output = {"record_id": 9, "place_type": "food", "place_type_label": "음식점", "place_type_evidence": "음식점", "categories": ["food"],
              "facets": [facet("menu", "유자하이볼", ["맛있었다"], ["food"], "치킨이 맛있었다.")]}
    result = service_for([output]).analyze([record]).analyses[0]

    assert result.facets == []


def test_unknown_place_type_stays_unknown_without_supported_evidence():
    record = make_record(10, "라운지", "넓어서 좋았다.")
    output = {"record_id": 10, "place_type": "cafe", "place_type_label": "카페", "place_type_evidence": "조용한 카페", "categories": ["cafe"], "facets": []}
    result = service_for([output]).analyze([record]).analyses[0]

    assert result.place_type == PlaceType.UNKNOWN
    assert result.categories == []
    assert result.facets == []
    assert result.evidence_status == EvidenceStatus.UNKNOWN


@pytest.mark.parametrize("status", [400, 401, 403, 429, 500, 503])
def test_http_status_errors_are_classified_without_logging_payload_or_credentials(status, caplog):
    caplog.set_level("INFO", logger="uvicorn.error")
    record = make_record(31, "광주 무등산 공원", "풍경이 아름다웠다.")

    def fail(*args, **kwargs):
        request = httpx.Request("POST", "https://openrouter.ai/api/v1/chat/completions")
        response = (httpx.Response(status, request=request,
                                   json={"error": {"code": "schema_keyword_not_supported", "message": "sensitive provider body"}})
                    if status == 400 else httpx.Response(status, request=request, text="sensitive provider body"))
        raise httpx.HTTPStatusError("must not be logged", request=request, response=response)

    result = RecordPreferenceAnalysisService(
        api_key="secret-test-token", model="test-model", post_json=fail
    ).analyze([record])

    assert result.analyses[0].evidence_status == EvidenceStatus.UNAVAILABLE
    assert result.analyses[0].categories == [RecommendationCategory.NATURE]
    assert "http_status=" + str(status) in caplog.text
    assert "provider_error_category=" in caplog.text
    if status == 400:
        assert "provider_error_code=schema_keyword_not_supported" in caplog.text
    assert "secret-test-token" not in caplog.text
    assert "sensitive provider body" not in caplog.text
    assert record.content not in caplog.text


def test_provider_400_logs_only_allowlisted_schema_keyword_and_param(caplog):
    caplog.set_level("INFO", logger="uvicorn.error")
    record = make_record(32, "synthetic cafe", "synthetic quiet place")

    def fail(*args, **kwargs):
        request = httpx.Request("POST", "https://openrouter.ai/api/v1/chat/completions")
        response = httpx.Response(400, request=request, json={"error": {
            "code": 400,
            "param": "response_format.json_schema.schema.properties.facets.items.properties.features.items",
            "message": "minLength unsupported; private phrase MUST_NOT_LOG",
        }})
        raise httpx.HTTPStatusError("private phrase MUST_NOT_LOG", request=request, response=response)

    RecordPreferenceAnalysisService(api_key="test-key", model="test-model", post_json=fail).analyze([record])

    assert "provider_error_code=400" in caplog.text
    assert "provider_error_schema_keyword=minLength" in caplog.text
    assert "provider_error_param=response_format.json_schema.schema.properties.facets.items.properties.features.items" in caplog.text
    assert "MUST_NOT_LOG" not in caplog.text
    assert record.content not in caplog.text


def test_gemini_schema_object_properties_are_all_required_and_closed():
    schema = RecordPreferenceAnalysisService._SCHEMA["schema"]

    def visit(node):
        if not isinstance(node, dict):
            return
        if node.get("type") == "object":
            assert node.get("additionalProperties") is False
            assert set(node.get("required", [])) == set(node.get("properties", {}))
            for child in node.get("properties", {}).values():
                visit(child)
        if node.get("type") == "array":
            visit(node.get("items"))

    visit(schema)


def test_openrouter_failure_retains_literal_nature_and_menu_preferences_without_invention():
    records = [
        make_record(i, f"광주 공원 {i}", "산책길 풍경이 좋았다.")
        for i in range(1, 8)
    ] + [
        make_record(i, f"모호한 장소 {i}", "넓어서 좋았다.")
        for i in range(8, 14)
    ]

    def fail(*args, **kwargs):
        request = httpx.Request("POST", "https://openrouter.ai/api/v1/chat/completions")
        response = httpx.Response(429, request=request)
        raise httpx.HTTPStatusError("rate limited", request=request, response=response)

    result = RecordPreferenceAnalysisService(
        api_key="test-token", model="test-model", post_json=fail
    ).analyze(records)

    assert len(result.analyses) == 13
    assert sum(RecommendationCategory.NATURE in item.categories for item in result.analyses) == 7
    assert sum(item.place_type == PlaceType.UNKNOWN for item in result.analyses) == 6
    assert all(item.facets for item in result.analyses)
    assert all(not item.categories for item in result.analyses[7:])
    assert all(item.evidence_status == EvidenceStatus.UNAVAILABLE for item in result.analyses)


def test_trusted_kakao_category_precedes_model_place_type():
    record = make_record(11, "장소", "분위기가 좋았다.")
    output = {"record_id": 11, "place_type": "cafe", "place_type_label": "카페", "place_type_evidence": "장소", "categories": ["cafe"], "facets": []}
    result = service_for([output]).analyze(
        [record], place_metadata={11: RecordPlaceMetadata(kakao_category="음식점 > 술집 > 이자카야")}
    ).analyses[0]

    assert result.place_type == PlaceType.BAR
    assert RecommendationCategory.BAR in result.categories


def test_request_is_bounded_redacted_and_uses_structured_schema():
    captured = {}
    record = make_record(12, "카페", "문의 010-1234-5678 test@example.com https://example.com " + ("조용했다. " * 100))
    output = {"record_id": 12, "place_type": "cafe", "place_type_label": "카페", "place_type_evidence": "카페", "categories": ["cafe"], "facets": []}
    service = service_for([output], captured=captured)

    service.analyze([record])
    sent = captured["messages"][1]["content"]

    assert "010-1234-5678" not in sent
    assert "test@example.com" not in sent
    assert "https://example.com" not in sent
    assert len(json.loads(sent)["records"][0]["content"]) <= 500
    assert captured["response_format"]["json_schema"]["strict"] is True
    assert captured["stream"] is False
    schema_text = json.dumps(captured["response_format"]["json_schema"]["schema"])
    assert "minLength" not in schema_text and "maxLength" not in schema_text


def test_gemini_compatible_schema_preserves_yuzu_highball_and_skewer_facets():
    record = make_record(40, "광주 이자카야", "유자하이볼과 꼬치가 정말 맛있었다.")
    output = [{
        "record_id": 40, "place_type": "bar", "place_type_label": "이자카야",
        "place_type_evidence": "이자카야", "categories": ["bar", "food"],
        "facets": [
            facet("drink", "유자하이볼", [], ["bar"], "유자하이볼과 꼬치가 정말 맛있었다."),
            facet("food", "꼬치", [], ["bar", "food"], "유자하이볼과 꼬치가 정말 맛있었다."),
        ],
    }]
    captured = {}

    def capture(url, **kwargs):
        captured.update(url=url, **kwargs["json"])
        return response_for(output)

    result = RecordPreferenceAnalysisService(
        api_key="test-key", model="google/gemini-2.5-flash", post_json=capture,
    ).analyze([record], category="all").analyses[0]

    assert captured["url"] == "https://openrouter.ai/api/v1/chat/completions"
    assert captured["model"] == "google/gemini-2.5-flash"
    assert captured["response_format"]["type"] == "json_schema"
    assert captured["provider"] == {"require_parameters": True}
    assert captured["stream"] is False
    assert {item.target_text for item in result.facets} == {"유자하이볼", "꼬치"}
    assert all(RecommendationCategory.BAR in item.categories for item in result.facets)


@pytest.mark.parametrize("bad_content", ["not json", '{"records": "wrong"}', '{"records": [{"record_id": 13}]}'])
def test_malformed_provider_response_returns_no_invented_facets(bad_content):
    record = make_record(13, "카페", "딸기라떼가 맛있었다.")

    class Response:
        def raise_for_status(self):
            pass

        def json(self):
            return {"choices": [{"message": {"content": bad_content}}]}

    service = RecordPreferenceAnalysisService(api_key="test", model="test", post_json=lambda *a, **k: Response())
    result = service.analyze([record]).analyses[0]

    assert result.facets == []
    assert result.evidence_status == EvidenceStatus.UNAVAILABLE


def test_provider_failure_and_missing_configuration_keep_only_literal_local_fallback():
    record = make_record(14, "카페", "조용해서 좋았다.")
    failing = RecordPreferenceAnalysisService(
        api_key="test", model="test", post_json=lambda *a, **k: (_ for _ in ()).throw(httpx.ConnectError("offline"))
    )
    failed = failing.analyze([record]).analyses[0]
    unconfigured = RecordPreferenceAnalysisService(api_key="", model="")
    missing = unconfigured.analyze([record]).analyses[0]

    assert [facet.target_text for facet in failed.facets] == ["조용"]
    assert [facet.target_text for facet in missing.facets] == ["조용"]
    assert failed.evidence_status == EvidenceStatus.UNAVAILABLE
    assert missing.evidence_status == EvidenceStatus.UNAVAILABLE


def test_truncates_record_count_to_cost_budget():
    records = [make_record(i, "카페", f"조용했다 {i}") for i in range(1, 4)]
    outputs = [{"record_id": i, "place_type": "cafe", "place_type_label": "카페", "place_type_evidence": "카페", "categories": ["cafe"], "facets": []} for i in (1, 2)]
    service = RecordPreferenceAnalysisService(
        api_key="test", model="test", max_records=2,
        post_json=lambda *a, **k: response_for(outputs),
    )
    result = service.analyze(records)

    assert [item.record_id for item in result.analyses] == [1, 2]
