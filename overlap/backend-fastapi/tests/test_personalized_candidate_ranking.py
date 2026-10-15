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


def test_only_verified_mixed_preference_matches_rank_when_categories_have_no_matching_subtype():
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

    # Broad categories alone do not establish the recorded quiet-space,
    # cheering, or scenery preferences.
    assert [item.kakao_place_id for item in ranked] == ["13", "14"]
    assert ranked[0].matched_keywords == ["citrus highball"]
    assert "skewers" in ranked[1].reason
    assert ranked[0].reason != ranked[1].reason
    assert "Tavily" not in ranked[0].reason and "Kakao" not in ranked[0].reason
    assert all("Unrelated Parking" != item.name for item in ranked)
    assert ranked[0].match_score == ranked[1].match_score


def test_generic_category_only_is_excluded_even_when_user_likes_the_broad_field():
    analyses = RecordPreferenceAnalysisResponse(analyses=[
        _analysis(1, PlaceType.CAFE, Category.CAFE, "indoor space", FacetTargetKind.SPACE,
                  features=("quiet",)),
    ])
    ranked = _build_category_recommendations(_result([
        _candidate(20, "Cafe without web details", [Category.CAFE], preference="quiet",
                   evidence_status=FeatureEvidenceStatus.UNAVAILABLE),
        _candidate(21, "Unrelated Restaurant", [Category.FOOD]),
    ]), analyses, Category.ALL)

    assert ranked == []

    bar_analysis = RecordPreferenceAnalysisResponse(analyses=[
        _analysis(2, PlaceType.BAR, Category.BAR, "yuzu highball", FacetTargetKind.DRINK),
    ])
    bar = _build_category_recommendations(_result([
        _candidate(22, "Izakaya without menu evidence", [Category.BAR], preference="yuzu highball",
                   evidence_status=FeatureEvidenceStatus.UNAVAILABLE),
    ]), bar_analysis, Category.ALL)
    assert bar == []


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


def test_overlapping_broad_category_labels_do_not_create_type_level_support():
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

    assert ranked == []


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

    assert mismatched_record == []

    matching_candidate = _candidate(92, "Synthetic Izakaya With Menu", [Category.BAR],
                                    preference="yuzu highball", record_id=91,
                                    evidence_status=FeatureEvidenceStatus.CONFIRMED)
    matched = _build_category_recommendations(_result([matching_candidate]), analyses, Category.ALL)

    assert len(matched) == 1
    assert matched[0].matched_keywords == ["yuzu highball"]


def test_rejection_diagnostics_are_anonymous_and_explain_category_and_evidence_gates(tmp_path, monkeypatch):
    import json
    from app import recommendation_diagnostics as diagnostics

    monkeypatch.setenv("OVERLAP_ENV", "development")
    monkeypatch.setenv("OVERLAP_AI_DIAGNOSTICS", "1")
    monkeypatch.setenv("OVERLAP_AI_DIAGNOSTICS_FILE", str(tmp_path / "trace.jsonl"))
    private_term = "private synthetic preference"
    analyses = RecordPreferenceAnalysisResponse(analyses=[
        _analysis(501, PlaceType.CAFE, Category.CAFE, private_term, FacetTargetKind.SPACE),
    ])
    unknown_category = _candidate(
        601, "private synthetic unknown venue", [], category_status=CategoryMatchStatus.UNKNOWN,
    )
    missing_feature = _candidate(
        602, "private synthetic cafe", [Category.CAFE], preference=private_term,
        evidence_status=FeatureEvidenceStatus.INSUFFICIENT,
    )

    token = diagnostics.begin()
    assert _build_category_recommendations(_result([unknown_category, missing_feature]), analyses, Category.ALL) == []
    diagnostics.finish(token, status_code=200, elapsed_ms=1)
    row = json.loads((tmp_path / "trace.jsonl").read_text(encoding="utf-8"))

    category = next(item for item in row["category_diagnostics"]
                    if item["status"] == "unknown")
    assert category["category_present"] is True
    assert category["group_code_class"] == "food"
    assert category["category_name_mapped"] is False
    assert category["mapped_categories"] == []
    assert category["reason"] == "no_recognized_category_evidence"

    category_gate = next(item for item in row["personalization_diagnostics"]
                         if item["reason"] == "category_not_confirmed")
    assert category_gate["positive_category_present"] is None
    assert category_gate["linkable_positive_facet_count"] is None

    personalization = next(item for item in row["personalization_diagnostics"]
                           if item["reason"] == "category_affinity_below_threshold")
    assert personalization["positive_category_present"] is True
    assert personalization["linkable_positive_facet_count"] == 1
    assert personalization["matched_positive_facet_count"] == 0
    assert personalization["type_evidence_accepted"] is False
    assert personalization["category_affinity_record_count"] == 1
    assert personalization["category_affinity_distinct_target_count"] == 1
    assert private_term not in (tmp_path / "trace.jsonl").read_text(encoding="utf-8")
    assert "private synthetic" not in (tmp_path / "trace.jsonl").read_text(encoding="utf-8")


@pytest.mark.parametrize(("place_type", "category", "facet_kind", "preference", "category_path"), [
    (PlaceType.FOOD, Category.FOOD, FacetTargetKind.MENU, "\ud55c\uc2dd", "\uc74c\uc2dd\uc810 > \ud55c\uc2dd"),
    (PlaceType.CAFE, Category.CAFE, FacetTargetKind.SPACE, "\ucee4\ud53c\uc804\ubb38\uc810", "\uce74\ud398 > \ucee4\ud53c\uc804\ubb38\uc810"),
    (PlaceType.ACTIVITY, Category.ACTIVITY, FacetTargetKind.ACTIVITY, "\ubbf8\uc220\uad00", "\ubb38\ud654,\uc608\uc220 > \ubbf8\uc220\uad00"),
])
def test_specific_kakao_subtype_matching_positive_facet_can_qualify_as_b(
        place_type, category, facet_kind, preference, category_path):
    analyses = RecordPreferenceAnalysisResponse(analyses=[
        _analysis(701, place_type, category, preference, facet_kind),
    ])
    candidate = _candidate(702, "Synthetic Specific Venue", [category])
    candidate.place.category_name = category_path
    candidate.feature_search_status = FeatureEvidenceStatus.UNAVAILABLE

    ranked = _build_category_recommendations(_result([candidate]), analyses, Category.ALL)

    assert len(ranked) == 1
    assert ranked[0].matched_keywords == [preference]
    assert category_path.split(" > ")[-1] in ranked[0].reason
    assert ranked[0].match_score < 0.5
    assert "맛볼 수" not in ranked[0].reason


def test_generic_kakao_business_category_does_not_qualify_as_b():
    analyses = RecordPreferenceAnalysisResponse(analyses=[
        _analysis(711, PlaceType.CAFE, Category.CAFE, "\uc870\uc6a9\ud55c \uacf5\uac04", FacetTargetKind.SPACE),
    ])
    candidate = _candidate(712, "Synthetic Generic Cafe", [Category.CAFE])
    candidate.place.category_name = "\uce74\ud398 > \uce74\ud398"
    candidate.feature_search_status = FeatureEvidenceStatus.UNAVAILABLE

    assert _build_category_recommendations(_result([candidate]), analyses, Category.ALL) == []


def test_tourism_group_without_nature_or_activity_subtype_does_not_get_type_grade_b():
    analyses = RecordPreferenceAnalysisResponse(analyses=[
        _analysis(721, PlaceType.NATURE, Category.NATURE, "\uc0b0\ucc45", FacetTargetKind.ACTIVITY),
    ])
    candidate = _candidate(722, "Synthetic Tourist Attraction", [Category.NATURE])
    candidate.place.category_group_code = "AT4"
    candidate.place.category_name = "\uc5ec\ud589 > \uad00\uad11\uba85\uc18c"
    candidate.feature_search_status = FeatureEvidenceStatus.UNAVAILABLE

    assert _build_category_recommendations(_result([candidate]), analyses, Category.ALL) == []


def test_unseen_preference_subtype_is_dynamic_and_single_positive_record_can_qualify():
    preference = "도자기 공예"
    analysis = _analysis(
        731, PlaceType.ACTIVITY, Category.ACTIVITY, preference, FacetTargetKind.ACTIVITY,
        intensity=0.8,
    )
    analyses = RecordPreferenceAnalysisResponse(analyses=[analysis])
    candidate = _candidate(732, "Synthetic Workshop", [Category.ACTIVITY])
    candidate.place.category_name = "공방 > 도자기 공예"
    candidate.feature_search_status = FeatureEvidenceStatus.UNAVAILABLE

    ranked = _build_category_recommendations(_result([candidate]), analyses, Category.ALL)

    assert len(ranked) == 1
    assert ranked[0].matched_keywords == [preference]
    assert "도자기 공예" in ranked[0].reason
    assert ranked[0].match_score < 0.5


def test_explicit_disliked_matching_kakao_subtype_is_excluded():
    analysis = _analysis(
        741, PlaceType.FOOD, Category.FOOD, "very spicy food", FacetTargetKind.MENU,
    )
    analysis.facets = [analysis.facets[0].model_copy(update={"polarity": "disliked"})]
    analyses = RecordPreferenceAnalysisResponse(analyses=[analysis])
    candidate = _candidate(742, "Synthetic Spicy Restaurant", [Category.FOOD])
    candidate.place.category_name = "restaurant > very spicy food"
    candidate.feature_search_status = FeatureEvidenceStatus.UNAVAILABLE

    assert _build_category_recommendations(_result([candidate]), analyses, Category.ALL) == []


@pytest.mark.parametrize("category", [
    Category.FOOD, Category.BAR, Category.CAFE, Category.NATURE, Category.ACTIVITY,
])
def test_repeated_broad_positive_category_supports_low_priority_b_without_claiming_a_feature(category):
    analyses = RecordPreferenceAnalysisResponse(analyses=[
        _analysis(801 + index, PlaceType.NATURE if category == Category.NATURE else PlaceType.FOOD,
                  category, f"recorded target {index}", FacetTargetKind.OTHER,
                  intensity=(0.7 + index * 0.05))
        for index in range(3)
    ])
    candidate = _candidate(811, "Synthetic Confirmed Category Venue", [category])
    candidate.place.category_name = "synthetic broad category"
    candidate.feature_search_status = FeatureEvidenceStatus.UNAVAILABLE

    ranked = _build_category_recommendations(_result([candidate]), analyses, Category.ALL)

    assert len(ranked) == 1
    assert ranked[0].match_score < 0.35
    assert ranked[0].matched_keywords == []
    assert all(f"recorded target {index}" not in ranked[0].reason for index in range(3))
    assert "Synthetic Confirmed Category Venue" in ranked[0].reason


def test_repeated_single_specific_preference_does_not_expand_to_broad_category_affinity():
    analyses = RecordPreferenceAnalysisResponse(analyses=[
        _analysis(821 + index, PlaceType.FOOD, Category.FOOD,
                  "single repeated specific menu", FacetTargetKind.MENU)
        for index in range(4)
    ])
    candidate = _candidate(831, "Synthetic Unrelated Restaurant", [Category.FOOD])
    candidate.place.category_name = "restaurant > restaurant"
    candidate.feature_search_status = FeatureEvidenceStatus.UNAVAILABLE

    assert _build_category_recommendations(_result([candidate]), analyses, Category.ALL) == []
