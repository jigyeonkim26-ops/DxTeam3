import json

from app.ai_recommendations import _analysis_cache_decision
from app.record_preference_analysis import (
    EvidenceStatus,
    FacetTargetKind,
    PlaceType,
    PreferenceFacet,
    RecommendationCategory,
    RecordPlaceMetadata,
    RecordPreferenceAnalysis,
    RecordPreferenceAnalysisResponse,
    RecordPreferenceAnalysisService,
)
from app.recommendation_record_adapter import RecommendationEmotionCode, RecommendationRecord


def make_record(record_id, name, content):
    return RecommendationRecord(
        record_id=record_id,
        user_id=19,
        place_id=record_id,
        place_name=name,
        content=content,
        emotion_code=RecommendationEmotionCode.LIKE,
        emotion_meaning="synthetic",
    )


def run_analysis(record, output, *, metadata=None, category=RecommendationCategory.ALL):
    def post_json(*args, **kwargs):
        return type("Response", (), {
            "raise_for_status": lambda self: None,
            "json": lambda self: {"choices": [{
                "finish_reason": "stop",
                "message": {"content": json.dumps(output, ensure_ascii=False)},
            }]},
        })()

    service = RecordPreferenceAnalysisService(api_key="mock", model="mock", post_json=post_json)
    return service.analyze([record], place_metadata=metadata, category=category)


def facet(kind, target, features, evidence, categories=None):
    return {
        "target_kind": kind,
        "target_text": target,
        "features": features,
        "categories": categories or [],
        "polarity": "liked",
        "evidence": evidence,
        "confidence": 0.9,
    }


def test_unknown_provider_type_recovers_cafe_from_explicit_record_wording():
    content = "\uCE74\uD398\uAC00 \uB113\uACE0 \uC870\uC6A9\uD574\uC11C \uC88B\uC558\uB2E4."
    record = make_record(101, "Example Venue", content)
    result = run_analysis(record, {"records": [{
        "record_id": 101,
        "place_type": "unknown",
        "place_type_label": None,
        "place_type_evidence": None,
        "categories": [],
        "facets": [facet("space", "\uCE74\uD398", ["\uB113\uACE0", "\uC870\uC6A9\uD574\uC11C"], content)],
    }]})

    analysis = result.analyses[0]
    assert analysis.place_type == PlaceType.CAFE
    assert analysis.place_type_evidence == "record_context_hint"
    assert analysis.categories == [RecommendationCategory.CAFE]
    assert analysis.facets[0].categories == [RecommendationCategory.CAFE]
    assert RecordPreferenceAnalysisService._filter_category(
        result, RecommendationCategory.CAFE,
    ).analyses


def test_unknown_type_keeps_literal_menu_domains_and_scopes_facets_separately():
    content = "\uC720\uC790\uD558\uC774\uBCFC\uACFC \uAF2C\uCE58\uAC00 \uB9DB\uC788\uC5C8\uB2E4."
    record = make_record(102, "Example Venue", content)
    result = run_analysis(record, {"records": [{
        "record_id": 102,
        "place_type": "unknown",
        "place_type_label": None,
        "place_type_evidence": None,
        "categories": [],
        "facets": [
            facet("drink", "\uC720\uC790\uD558\uC774\uBCFC", [], content),
            facet("food", "\uAF2C\uCE58", [], content),
        ],
    }]})

    analysis = result.analyses[0]
    assert analysis.place_type == PlaceType.UNKNOWN
    assert set(analysis.categories) == {RecommendationCategory.BAR, RecommendationCategory.FOOD}
    bar = RecordPreferenceAnalysisService._filter_category(result, RecommendationCategory.BAR)
    food = RecordPreferenceAnalysisService._filter_category(result, RecommendationCategory.FOOD)
    assert [item.target_text for item in bar.analyses[0].facets] == ["\uC720\uC790\uD558\uC774\uBCFC"]
    assert [item.target_text for item in food.analyses[0].facets] == ["\uAF2C\uCE58"]


def test_unknown_generic_facet_does_not_trust_model_category_or_create_category():
    content = "\uACF5\uAC04\uC774 \uB113\uC5B4\uC11C \uC88B\uC558\uB2E4."
    record = make_record(103, "Example Venue", content)
    result = run_analysis(record, {"records": [{
        "record_id": 103,
        "place_type": "unknown",
        "place_type_label": None,
        "place_type_evidence": None,
        "categories": ["cafe"],
        "facets": [facet("space", "\uACF5\uAC04", ["\uB113\uC5B4\uC11C"], content, ["cafe"])],
    }]})

    analysis = result.analyses[0]
    assert analysis.place_type == PlaceType.UNKNOWN
    assert analysis.categories == []
    assert analysis.facets[0].categories == []
    assert RecordPreferenceAnalysisService._filter_category(
        result, RecommendationCategory.CAFE,
    ).analyses == []


def test_trusted_place_metadata_overrides_provider_unknown_without_schema_change():
    record = make_record(104, "Example Venue", "\uB9E4\uC7A5\uC774 \uC870\uC6A9\uD574\uC11C \uC88B\uC558\uB2E4.")
    result = run_analysis(
        record,
        {"records": [{
            "record_id": 104,
            "place_type": "unknown",
            "place_type_label": None,
            "place_type_evidence": None,
            "categories": [],
            "facets": [facet("space", "\uB9E4\uC7A5", ["\uC870\uC6A9\uD574\uC11C"], record.content)],
        }]},
        metadata={104: RecordPlaceMetadata(kakao_category="\uC74C\uC2DD\uC810 > \uCE74\uD398")},
    )
    assert result.analyses[0].place_type == PlaceType.CAFE
    assert result.analyses[0].categories == [RecommendationCategory.CAFE]


def test_thirteen_records_keep_explicit_categories_while_unclassifiable_record_stays_unknown():
    records = []
    raw_rows = []
    for record_id in range(1, 13):
        content = "\uCE74\uD398\uAC00 \uC870\uC6A9\uD574\uC11C \uC88B\uC558\uB2E4."
        records.append(make_record(record_id, f"Venue {record_id}", content))
        raw_rows.append({
            "record_id": record_id, "place_type": "unknown", "place_type_label": None,
            "place_type_evidence": None, "categories": [],
            "facets": [facet("ambience", "\uCE74\uD398", ["\uC870\uC6A9\uD574\uC11C"], content)],
        })
    generic_content = "\uACF5\uAC04\uC774 \uB113\uC5B4\uC11C \uC88B\uC558\uB2E4."
    records.append(make_record(13, "Unclassified Venue", generic_content))
    raw_rows.append({
        "record_id": 13, "place_type": "unknown", "place_type_label": None,
        "place_type_evidence": None, "categories": [],
        "facets": [facet("space", "\uACF5\uAC04", ["\uB113\uC5B4\uC11C"], generic_content)],
    })

    result = RecordPreferenceAnalysisService(api_key="mock", model="mock", post_json=lambda *a, **k: type(
        "Response", (), {
            "raise_for_status": lambda self: None,
            "json": lambda self: {"choices": [{"finish_reason": "stop", "message": {
                "content": json.dumps({"records": raw_rows}, ensure_ascii=False),
            }}]},
        }
    )()).analyze(records)

    cafe = RecordPreferenceAnalysisService._filter_category(result, RecommendationCategory.CAFE)
    assert len(result.analyses) == 13
    assert len(cafe.analyses) == 12
    assert result.analyses[-1].place_type == PlaceType.UNKNOWN
    assert result.analyses[-1].categories == []


def test_analysis_cache_reuses_partial_success_but_rejects_unusable_and_unclassified_facet_sets():
    good = RecordPreferenceAnalysis(
        record_id=1, place_type=PlaceType.FOOD, categories=[RecommendationCategory.FOOD],
        emotion=RecommendationEmotionCode.LIKE, emotion_intensity=0.8,
        facets=[], evidence_status=EvidenceStatus.VERIFIED,
    )
    failed = good.model_copy(update={"record_id": 2, "evidence_status": EvidenceStatus.UNAVAILABLE})
    assert _analysis_cache_decision(RecordPreferenceAnalysisResponse(analyses=[good, failed])) == (
        True, "partial_or_complete_analysis",
    )
    assert _analysis_cache_decision(RecordPreferenceAnalysisResponse(analyses=[failed])) == (
        False, "all_records_unavailable",
    )
    unresolved = good.model_copy(update={
        "place_type": PlaceType.UNKNOWN,
        "categories": [],
        "facets": [PreferenceFacet(
            target_kind=FacetTargetKind.SPACE,
            target_text="\u0073\u0070\u0061\u0063\u0065",
            features=["\u0071\u0075\u0069\u0065\u0074"],
            categories=[], polarity="liked", evidence="synthetic", confidence=0.8,
        )],
        "evidence_status": EvidenceStatus.PARTIAL,
    })
    assert _analysis_cache_decision(RecordPreferenceAnalysisResponse(analyses=[unresolved])) == (
        False, "all_categories_unresolved_with_facets",
    )
