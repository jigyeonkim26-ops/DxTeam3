import pytest

from app.ai_recommendations import _build_category_recommendations
from app.place_candidate_search_service import (
    CandidateSearchResult,
    CategoryMatchStatus,
    FeatureEvidenceStatus,
    KakaoPlaceCandidate,
    PlaceCandidateEvidence,
    PlaceCategoryClassification,
    PreferenceEvidence,
    ProviderStatus,
)
from app.record_preference_analysis import (
    EvidenceStatus,
    FacetTargetKind,
    PlaceType,
    PreferenceFacet,
    RecordPreferenceAnalysis,
    RecordPreferenceAnalysisResponse,
    RecommendationCategory as Category,
)


def _analysis(record_id, place_type, category, target, kind, *, features=(), intensity=1.0, confidence=0.95):
    return RecordPreferenceAnalysis(
        record_id=record_id,
        place_name=place_type.value,
        place_type=place_type,
        categories=[category],
        emotion="LOVE",
        emotion_intensity=intensity,
        evidence_status=EvidenceStatus.VERIFIED,
        facets=[PreferenceFacet(
            target_kind=kind,
            target_text=target,
            features=list(features),
            categories=[category],
            polarity="liked",
            evidence="synthetic fixture evidence",
            confidence=confidence,
        )],
    )


def _candidate(place_id, name, categories, *, preference=None, record_id=1,
               evidence_status=FeatureEvidenceStatus.INSUFFICIENT, category_status=CategoryMatchStatus.CONFIRMED):
    place = KakaoPlaceCandidate(
        kakao_place_id=str(place_id), place_name=name,
        address="Gwangju Seo-gu", latitude=35.15, longitude=126.92,
        category_group_code="FD6", category_name="synthetic verified category",
        place_url=f"https://place.map.kakao.com/{place_id}",
    )
    evidence = []
    if preference:
        evidence.append(PreferenceEvidence(
            record_id=record_id, preference=preference, status=evidence_status,
            evidence_text="synthetic verified detail" if evidence_status == FeatureEvidenceStatus.CONFIRMED else None,
            evidence_url="https://example.test/place-detail" if evidence_status == FeatureEvidenceStatus.CONFIRMED else None,
        ))
    return PlaceCandidateEvidence(
        place=place,
        classification=PlaceCategoryClassification(
            requested_category=Category.ALL, categories=categories,
            status=category_status, evidence=["synthetic Kakao category"],
        ),
        preference_evidence=evidence,
        feature_search_status=evidence_status,
    )


def _result(candidates):
    return CandidateSearchResult(
        category=Category.ALL, region="Gwangju", kakao_status=ProviderStatus.COMPLETE,
        tavily_status=ProviderStatus.PARTIAL, kakao_call_count=3, tavily_call_count=3,
        candidates=candidates,
    )


def test_all_ranks_verified_mixed_preferences_above_category_only_and_ignores_search_order():
    analyses = RecordPreferenceAnalysisResponse(analyses=[
        _analysis(1, PlaceType.BAR, Category.BAR, "citrus highball", FacetTargetKind.DRINK),
        _analysis(5, PlaceType.BAR, Category.BAR, "skewers", FacetTargetKind.FOOD),
        _analysis(2, PlaceType.CAFE, Category.CAFE, "indoor space", FacetTargetKind.SPACE,
                  features=("quiet", "spacious"), intensity=1.0),
        _analysis(3, PlaceType.ACTIVITY, Category.ACTIVITY, "stadium cheering", FacetTargetKind.ACTIVITY,
                  intensity=0.7),
        _analysis(4, PlaceType.NATURE, Category.NATURE, "scenery", FacetTargetKind.SCENERY,
                  intensity=0.5),
    ])
    # Nature arrives first from Kakao, but a verified bar-menu match ranks first.
    candidates = [
        _candidate(10, "Nature Place", [Category.NATURE]),
        _candidate(11, "Cafe Place", [Category.CAFE], preference="quiet", record_id=2),
        _candidate(12, "Stadium", [Category.ACTIVITY]),
        _candidate(13, "Izakaya", [Category.BAR], preference="citrus highball",
                   evidence_status=FeatureEvidenceStatus.CONFIRMED),
        _candidate(14, "Skewer Bar", [Category.BAR], preference="skewers", record_id=5,
                   evidence_status=FeatureEvidenceStatus.CONFIRMED),
        _candidate(15, "Unrelated Parking", [Category.FOOD]),
    ]

    ranked = _build_category_recommendations(_result(candidates), analyses, Category.ALL)

    assert [item.kakao_place_id for item in ranked] == ["13", "14", "11", "12", "10"]
    assert ranked[0].matched_keywords == ["citrus highball"]
    assert "skewers" in ranked[1].reason
    assert ranked[0].reason != ranked[1].reason
    assert "Tavily" not in ranked[0].reason and "Kakao" not in ranked[0].reason
    assert all("Unrelated Parking" != item.name for item in ranked)
    assert ranked[0].match_score == ranked[1].match_score
    assert "\uD655\uC778\uB3FC\uC11C" in ranked[0].reason
    assert "\uAC00\uBCF4\uC154\uB3C4 \uC88B\uC744 \uAC83 \uAC19\uC544\uC694" in ranked[0].reason


def test_type_only_is_weak_honest_level_b_and_unrelated_category_is_excluded():
    analyses = RecordPreferenceAnalysisResponse(analyses=[
        _analysis(1, PlaceType.CAFE, Category.CAFE, "indoor space", FacetTargetKind.SPACE,
                  features=("quiet",)),
    ])
    ranked = _build_category_recommendations(_result([
        _candidate(20, "Cafe without web details", [Category.CAFE], preference="quiet",
                   evidence_status=FeatureEvidenceStatus.UNAVAILABLE),
        _candidate(21, "Unrelated Restaurant", [Category.FOOD]),
    ]), analyses, Category.ALL)

    assert len(ranked) == 1
    assert ranked[0].kakao_place_id == "20"
    assert ranked[0].matched_keywords == []
    assert ranked[0].match_score <= 0.30
    assert "카페" in ranked[0].reason
    assert "조용" not in ranked[0].reason

    bar_analysis = RecordPreferenceAnalysisResponse(analyses=[
        _analysis(2, PlaceType.BAR, Category.BAR, "yuzu highball", FacetTargetKind.DRINK),
    ])
    bar = _build_category_recommendations(_result([
        _candidate(22, "Izakaya without menu evidence", [Category.BAR], preference="yuzu highball",
                   evidence_status=FeatureEvidenceStatus.UNAVAILABLE),
    ]), bar_analysis, Category.ALL)[0]
    assert "\uC220\uC9D1" in bar.reason
    assert "yuzu highball" not in bar.reason
    assert bar.reason != ranked[0].reason


def test_known_place_type_without_concrete_preferences_does_not_create_a_recommendation():
    fallback = RecordPreferenceAnalysisResponse(analyses=[RecordPreferenceAnalysis(
        record_id=44, place_name="무등산 공원", place_type=PlaceType.NATURE,
        place_type_label="공원", place_type_evidence="place_name_hint",
        categories=[Category.NATURE], emotion="LOVE", emotion_intensity=1.0,
        facets=[], evidence_status=EvidenceStatus.UNAVAILABLE,
    )])
    ranked = _build_category_recommendations(_result([
        _candidate(44, "Kakao Nature Park", [Category.NATURE]),
    ]), fallback, Category.ALL)

    assert ranked == []


def test_overlapping_category_labels_do_not_double_count_one_record_type_support():
    analysis = RecordPreferenceAnalysis(
        record_id=90, place_name="synthetic cafe", place_type=PlaceType.CAFE,
        categories=[Category.CAFE, Category.FOOD], emotion="LOVE", emotion_intensity=1.0,
        evidence_status=EvidenceStatus.VERIFIED, facets=[PreferenceFacet(
            target_kind=FacetTargetKind.SPACE, target_text="indoor space", features=["spacious"],
            categories=[Category.CAFE, Category.FOOD], polarity="liked",
            evidence="synthetic preference", confidence=0.95,
        )],
    )
    analyses = RecordPreferenceAnalysisResponse(analyses=[analysis])
    candidate = _candidate(90, "Synthetic Cafe", [Category.CAFE, Category.FOOD])

    ranked = _build_category_recommendations(_result([candidate]), analyses, Category.ALL)

    assert len(ranked) == 1
    assert ranked[0].match_score == pytest.approx(0.12)
    assert ranked[0].matched_keywords == []


def test_first_page_breaks_near_ties_toward_a_distinct_verified_preference():
    analyses = RecordPreferenceAnalysisResponse(analyses=[
        _analysis(1, PlaceType.BAR, Category.BAR, "유자하이볼", FacetTargetKind.DRINK),
        _analysis(2, PlaceType.BAR, Category.BAR, "꼬치", FacetTargetKind.FOOD),
    ])
    candidates = [
        _candidate(1, "A Highball Bar", [Category.BAR], preference="유자하이볼",
                   record_id=1, evidence_status=FeatureEvidenceStatus.CONFIRMED),
        _candidate(2, "B Highball Bar", [Category.BAR], preference="유자하이볼",
                   record_id=1, evidence_status=FeatureEvidenceStatus.CONFIRMED),
        _candidate(3, "C Skewer Bar", [Category.BAR], preference="꼬치",
                   record_id=2, evidence_status=FeatureEvidenceStatus.CONFIRMED),
        _candidate(4, "D Skewer Bar", [Category.BAR], preference="꼬치",
                   record_id=2, evidence_status=FeatureEvidenceStatus.CONFIRMED),
    ]

    ranked = _build_category_recommendations(_result(candidates), analyses, Category.ALL)

    assert ranked[0].matched_keywords == ["유자하이볼"]
    assert ranked[1].matched_keywords == ["꼬치"]
    assert len(ranked) <= 10


def test_confirmed_tavily_feature_requires_same_record_facet_for_level_a():
    analyses = RecordPreferenceAnalysisResponse(analyses=[
        _analysis(91, PlaceType.BAR, Category.BAR, "yuzu highball", FacetTargetKind.DRINK),
    ])
    candidate = _candidate(91, "Synthetic Izakaya", [Category.BAR], preference="yuzu highball",
                           record_id=999, evidence_status=FeatureEvidenceStatus.CONFIRMED)

    mismatched_record = _build_category_recommendations(_result([candidate]), analyses, Category.ALL)

    assert len(mismatched_record) == 1
    assert mismatched_record[0].matched_keywords == []

    matching_candidate = _candidate(92, "Synthetic Izakaya With Menu", [Category.BAR],
                                    preference="yuzu highball", record_id=91,
                                    evidence_status=FeatureEvidenceStatus.CONFIRMED)
    matched = _build_category_recommendations(_result([matching_candidate]), analyses, Category.ALL)

    assert len(matched) == 1
    assert matched[0].matched_keywords == ["yuzu highball"]
