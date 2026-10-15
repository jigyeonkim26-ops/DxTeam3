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


def response_for(records, *, finish_reason="stop", content=None):
    class Response:
        def raise_for_status(self):
            pass

        def json(self):
            return {"choices": [{
                "finish_reason": finish_reason,
                "message": {"content": content if content is not None else json.dumps({"records": records}, ensure_ascii=False)},
            }]}

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


def test_ambiguous_place_name_fragment_does_not_override_food_content():
    record = make_record(701, "산등무", "낙지볶음은 맛있었지만 너무 매웠다.")
    result = service_for([{
        "record_id": 701, "place_type": "nature", "place_type_label": "산",
        "place_type_evidence": "산", "categories": ["nature"], "facets": [],
    }]).analyze([record]).analyses[0]

    assert result.place_type == PlaceType.UNKNOWN
    assert result.categories == []


def test_explicit_record_place_context_beats_ambiguous_name_and_negative_feature_is_not_liked():
    record = make_record(702, "산등무", "음식점에서 낙지볶음은 맛있었지만 너무 매웠다.")
    result = service_for([{
        "record_id": 702, "place_type": "food", "place_type_label": "음식점",
        "place_type_evidence": "음식점", "categories": ["food"],
        "facets": [
            facet("food", "낙지볶음", ["맛있었지만"], ["food"], "낙지볶음은 맛있었지만"),
            facet("food", "낙지볶음", ["너무 매웠다"], ["food"], "너무 매웠다", "liked"),
        ],
    }]).analyze([record]).analyses[0]

    assert result.place_type == PlaceType.FOOD
    assert any(row.target_text == "낙지볶음" for row in result.facets)
    assert all("너무 매웠다" not in row.features or row.polarity != "liked" for row in result.facets)


def test_thirteen_positive_records_keep_eight_detailed_tastes_and_ignore_empty_notes():
    examples = [
        ("아카이타코", "타코야끼가 바삭하고 촉촉해서 좋았다.", "food", "타코야끼", ["바삭하고", "촉촉해서"], "food"),
        ("산등무", "음식점에서 낙지볶음은 맛있었지만 너무 매웠다.", "food", "낙지볶음", ["맛있었지만"], "food"),
        ("아오모모", "카페 매장이 넓고 조용해서 좋았다. 롤케이크도 맛있었다.", "cafe", "롤케이크", ["맛있었다"], "cafe"),
        ("대로", "이자카야 유자하이볼과 꼬치가 맛있었다.", "bar", "유자하이볼", ["맛있었다"], "bar"),
        ("구르메쇼쿠도", "식당 스키야끼를 먹고 죽도 맛있었다.", "food", "스키야끼", ["맛있었다"], "food"),
        ("통큰대구막창", "음식점 냉삼과 막창이 맛있었다.", "food", "막창", ["맛있었다"], "food"),
        ("인투", "음식점 빠에야가 정말 맛있었다.", "food", "빠에야", ["정말 맛있었다"], "food"),
        ("대구실내체육관", "농구 경기와 홈 개막전 이벤트가 즐거웠다.", "activity", "농구 경기", ["즐거웠다"], "activity"),
    ]
    records = [make_record(index, name, content) for index, (name, content, *_rest) in enumerate(examples, 1)]
    records.extend(make_record(index, f"메모 {index}", content)
                   for index, content in zip(range(9, 14), ["zzz", "good", "ㅋ", "집가고 싶다", "ㅎ"]))
    outputs = []
    for index, (name, _content, place_type, target, features, category) in enumerate(examples, 1):
        outputs.append({
            "record_id": index, "place_type": place_type, "place_type_label": place_type,
            "place_type_evidence": "농구 경기" if place_type == "activity" else None,
            "categories": [category],
            "facets": [facet("activity" if place_type == "activity" else "menu", target, features,
                             [category], _content)],
        })
    outputs.extend({"record_id": index, "place_type": "unknown", "place_type_label": None,
                    "place_type_evidence": None, "categories": [], "facets": []}
                   for index in range(9, 14))

    result = service_for(outputs).analyze(records).analyses

    assert len(result) == 13
    assert sum(any(row.polarity == "liked" for row in item.facets) for item in result) == 8
    assert all(not item.facets and not item.categories for item in result[8:])


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


def test_request_is_bounded_redacted_and_uses_json_mode_with_complete_contract():
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
    assert captured["response_format"] == {"type": "json_object"}
    assert captured["stream"] is False
    system_prompt = captured["messages"][0]["content"]
    for required_name in ("records array", "record_id", "place_type_evidence", "target_kind", "target_text",
                          "features", "polarity", "evidence", "confidence"):
        assert required_name in system_prompt
    assert "Copy feature wording exactly" in system_prompt
    assert "조용해서" in system_prompt and "조용한" in system_prompt


def test_json_mode_request_preserves_yuzu_highball_and_skewer_facets():
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
    assert captured["response_format"] == {"type": "json_object"}
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


def test_record_count_output_token_budget_scales_with_1200_minimum():
    captured = {}
    records = [make_record(51, "synthetic cafe", "quiet"), make_record(52, "synthetic cafe", "wide")]
    outputs = [
        {"record_id": record.record_id, "place_type": "cafe", "place_type_label": "cafe",
         "place_type_evidence": record.place_name, "categories": ["cafe"], "facets": []}
        for record in records
    ]
    service_for(outputs, captured=captured).analyze(records)

    assert captured["max_tokens"] == 1200
    assert captured["response_format"] == {"type": "json_object"}
    assert RecordPreferenceAnalysisService._max_output_tokens(1) == 1200
    assert RecordPreferenceAnalysisService._max_output_tokens(2) == 1200
    assert RecordPreferenceAnalysisService._max_output_tokens(13) == 7800
    assert RecordPreferenceAnalysisService._max_output_tokens(30) == 12000


def test_json_parser_reports_truncated_response_without_logging_response_content(caplog):
    caplog.set_level("INFO", logger="uvicorn.error")
    record = make_record(53, "synthetic cafe", "quiet")
    result = RecordPreferenceAnalysisService(
        api_key="test", model="test", post_json=lambda *a, **k: response_for([], content='{"records":[{"record_id":53')
    ).analyze([record]).analyses[0]

    assert result.evidence_status == EvidenceStatus.UNAVAILABLE
    assert "stage=json_parse reason=truncated_json" in caplog.text
    assert "record_id" not in caplog.text


def test_empty_records_response_is_unavailable_and_classified(caplog):
    caplog.set_level("INFO", logger="uvicorn.error")
    record = make_record(54, "synthetic cafe", "quiet")
    result = RecordPreferenceAnalysisService(
        api_key="test", model="test", post_json=lambda *a, **k: response_for([])
    ).analyze([record]).analyses[0]

    assert result.evidence_status == EvidenceStatus.UNAVAILABLE
    assert "stage=records_validation reason=records_empty" in caplog.text


def test_finish_reason_length_is_detected_before_json_parsing(caplog):
    caplog.set_level("INFO", logger="uvicorn.error")
    record = make_record(55, "synthetic cafe", "quiet")
    result = RecordPreferenceAnalysisService(
        api_key="test", model="test",
        post_json=lambda *a, **k: response_for([], finish_reason="length", content='{"records":['),
    ).analyze([record]).analyses[0]

    assert result.evidence_status == EvidenceStatus.UNAVAILABLE
    assert "stage=finish_reason reason=token_limit finish_reason=length" in caplog.text
    assert "truncated_json" not in caplog.text


def test_missing_required_record_fields_are_classified_and_use_fallback(caplog):
    caplog.set_level("INFO", logger="uvicorn.error")
    record = make_record(56, "synthetic cafe", "quiet")
    result = RecordPreferenceAnalysisService(
        api_key="test", model="test", post_json=lambda *a, **k: response_for([{"record_id": 56}])
    ).analyze([record]).analyses[0]

    assert result.evidence_status == EvidenceStatus.UNAVAILABLE
    assert "record_failure_counts=required_fields_missing:1" in caplog.text


def test_pydantic_type_error_isolated_to_its_record(caplog):
    caplog.set_level("INFO", logger="uvicorn.error")
    records = [make_record(57, "synthetic cafe", "quiet"), make_record(58, "synthetic cafe", "wide")]
    invalid = {"record_id": 57, "place_type": "not_a_place_type", "place_type_label": "cafe",
               "place_type_evidence": "synthetic cafe", "categories": ["cafe"], "facets": []}
    valid = {"record_id": 58, "place_type": "cafe", "place_type_label": "cafe",
             "place_type_evidence": "synthetic cafe", "categories": ["cafe"], "facets": []}
    results = RecordPreferenceAnalysisService(
        api_key="test", model="test", post_json=lambda *a, **k: response_for([invalid, valid])
    ).analyze(records).analyses

    assert results[0].evidence_status == EvidenceStatus.UNAVAILABLE
    assert results[1].evidence_status != EvidenceStatus.UNAVAILABLE
    assert "record_failure_counts=pydantic_validation_error:1" in caplog.text
    assert "pydantic_error_types=enum:1" in caplog.text
    assert "local_fallback=1" in caplog.text


def test_model_facets_with_unsupported_record_evidence_are_rejected(caplog):
    caplog.set_level("INFO", logger="uvicorn.error")
    record = make_record(59, "synthetic cafe", "A quiet room was nice.")
    output = {"record_id": 59, "place_type": "cafe", "place_type_label": "cafe",
              "place_type_evidence": "synthetic cafe", "categories": ["cafe"],
              "facets": [facet("facility", "parking", ["quiet"], ["cafe"], "A quiet room was nice.")]}
    result = RecordPreferenceAnalysisService(
        api_key="test", model="test", post_json=lambda *a, **k: response_for([output])
    ).analyze([record]).analyses[0]

    assert result.facets == []
    assert result.evidence_status == EvidenceStatus.PARTIAL
    assert "evidence_rejected_facets=1" in caplog.text
    assert "stage=evidence_validation reason=source_evidence_rejected failure_counts=target_not_in_record:1" in caplog.text
    assert "source=provider" in caplog.text


def test_successful_provider_result_and_fallback_are_distinguished_in_safe_logs(caplog):
    caplog.set_level("INFO", logger="uvicorn.error")
    record = make_record(60, "synthetic cafe", "quiet")
    output = {"record_id": 60, "place_type": "cafe", "place_type_label": "cafe",
              "place_type_evidence": "synthetic cafe", "categories": ["cafe"], "facets": []}
    RecordPreferenceAnalysisService(
        api_key="test", model="test", post_json=lambda *a, **k: response_for([output])
    ).analyze([record])

    assert "http_status=200 finish_reason=stop json_parse=ok records_array_count=1" in caplog.text
    assert "pydantic_validated=1" in caplog.text
    assert "source=provider provider_analyzed=1 local_fallback=0" in caplog.text
    assert "quiet" not in caplog.text


@pytest.mark.parametrize("body,reason", [
    ({}, "choices_missing_or_empty"),
    ({"choices": [{"message": {}}]}, "content_missing_or_not_text"),
])
def test_response_extraction_failures_have_safe_stage_reason_and_fallback(body, reason, caplog):
    caplog.set_level("INFO", logger="uvicorn.error")
    record = make_record(61, "synthetic cafe", "quiet")

    class Response:
        def raise_for_status(self):
            pass

        def json(self):
            return body

    result = RecordPreferenceAnalysisService(
        api_key="test", model="test", post_json=lambda *a, **k: Response()
    ).analyze([record]).analyses[0]

    assert result.evidence_status == EvidenceStatus.UNAVAILABLE
    assert f"stage=response_extraction reason={reason}" in caplog.text
    assert "source=local_fallback" in caplog.text


def test_missing_records_array_is_classified_separately_from_json_parse(caplog):
    caplog.set_level("INFO", logger="uvicorn.error")
    record = make_record(62, "synthetic cafe", "quiet")
    result = RecordPreferenceAnalysisService(
        api_key="test", model="test",
        post_json=lambda *a, **k: response_for([], content='{"analysis":[]}'),
    ).analyze([record]).analyses[0]

    assert result.evidence_status == EvidenceStatus.UNAVAILABLE
    assert "stage=records_validation reason=records_field_missing" in caplog.text



def test_analyze_accepts_two_synthetic_korean_records_through_real_validation_flow(caplog):
    """Exercise analyze() with a mocked OpenRouter envelope; no validator wrappers."""
    caplog.set_level("INFO", logger="uvicorn.error")
    izakaya_content = "\uc720\uc790\ud558\uc774\ubcfc\uacfc \uaf2c\uce58\uac00 \ub9db\uc788\uc5c8\ub2e4."
    cafe_content = "\ub9e4\uc7a5\uc774 \ub113\uace0 \uc870\uc6a9\ud574\uc11c \uc88b\uc558\ub2e4."
    records = [
        make_record(701, "\uc774\uc790\uce74\uc57c", izakaya_content),
        make_record(702, "\uce74\ud398", cafe_content, RecommendationEmotionCode.LIKE),
    ]
    outputs = [
        {
            "record_id": 701,
            "place_type": "bar",
            "place_type_label": "\uc774\uc790\uce74\uc57c",
            "place_type_evidence": "\uc774\uc790\uce74\uc57c",
            "categories": ["bar", "food"],
            "facets": [
                facet("drink", "\uc720\uc790\ud558\uc774\ubcfc", ["\ub9db\uc788\uc5c8\ub2e4"], ["bar"], izakaya_content),
                facet("food", "\uaf2c\uce58", ["\ub9db\uc788\uc5c8\ub2e4"], ["bar", "food"], izakaya_content),
            ],
        },
        {
            "record_id": 702,
            "place_type": "cafe",
            "place_type_label": "\uce74\ud398",
            "place_type_evidence": "\uce74\ud398",
            "categories": ["cafe"],
            "facets": [
                facet("space", "\ub9e4\uc7a5", ["\ub113\uace0"], ["cafe"], cafe_content),
                facet("ambience", "\ub9e4\uc7a5", ["\uc870\uc6a9\ud574\uc11c"], ["cafe"], cafe_content),
            ],
        },
    ]
    captured = {}

    def post_json(url, *, headers, json, timeout):
        captured.update(url=url, payload=json, timeout=timeout)
        return response_for(outputs, finish_reason="stop")

    result = RecordPreferenceAnalysisService(
        api_key="synthetic-test-key", model="google/gemini-2.5-flash", post_json=post_json,
    ).analyze(records, category="all")

    assert len(result.analyses) == 2
    izakaya, cafe = result.analyses
    assert izakaya.evidence_status == EvidenceStatus.VERIFIED
    assert cafe.evidence_status == EvidenceStatus.VERIFIED
    assert {item.target_text for item in izakaya.facets} == {"\uc720\uc790\ud558\uc774\ubcfc", "\uaf2c\uce58"}
    assert all(RecommendationCategory.BAR in item.categories for item in izakaya.facets)
    assert {feature for item in cafe.facets for feature in item.features} == {"\ub113\uace0", "\uc870\uc6a9\ud574\uc11c"}
    assert all(RecommendationCategory.CAFE in item.categories for item in cafe.facets)
    assert captured["url"] == RecordPreferenceAnalysisService.API_URL
    assert captured["payload"]["stream"] is False
    assert captured["payload"]["response_format"] == {"type": "json_object"}
    assert captured["payload"]["max_tokens"] == 1200
    assert "http_status=200 finish_reason=stop json_parse=ok records_array_count=2" in caplog.text
    assert "required_fields_validated=2 pydantic_validated=2 evidence_accepted_facets=4" in caplog.text
    assert "source=provider provider_analyzed=2 local_fallback=0" in caplog.text
    assert "\uc720\uc790\ud558\uc774\ubcfc" not in caplog.text
    assert izakaya_content not in caplog.text
    assert cafe_content not in caplog.text



def test_korean_feature_inflection_requires_literal_source_wording(caplog):
    caplog.set_level("INFO", logger="uvicorn.error")
    content = "\ub9e4\uc7a5\uc774 \ub113\uace0 \uc870\uc6a9\ud574\uc11c \uc88b\uc558\ub2e4."
    records = [
        make_record(703, "\uce74\ud398", content, RecommendationEmotionCode.LIKE),
        make_record(704, "\uce74\ud398", content, RecommendationEmotionCode.LIKE),
    ]
    outputs = []
    for record, feature in zip(records, ("\uc870\uc6a9\ud55c", "\uc870\uc6a9\ud574\uc11c")):
        outputs.append({
            "record_id": record.record_id,
            "place_type": "cafe",
            "place_type_label": "\uce74\ud398",
            "place_type_evidence": "\uce74\ud398",
            "categories": ["cafe"],
            "facets": [facet("ambience", "\ub9e4\uc7a5", [feature], ["cafe"], content)],
        })

    analyses = RecordPreferenceAnalysisService(
        api_key="synthetic-test-key", model="google/gemini-2.5-flash",
        post_json=lambda *a, **k: response_for(outputs),
    ).analyze(records).analyses

    assert analyses[0].facets == []
    assert analyses[0].evidence_status == EvidenceStatus.PARTIAL
    assert [item.features for item in analyses[1].facets] == [["\uc870\uc6a9\ud574\uc11c"]]
    assert analyses[1].evidence_status == EvidenceStatus.VERIFIED
    assert "feature_not_in_record:1" in caplog.text
    assert "provider_analyzed=2 local_fallback=0" in caplog.text
