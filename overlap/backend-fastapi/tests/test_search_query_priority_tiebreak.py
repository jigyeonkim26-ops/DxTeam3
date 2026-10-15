from app.ai_recommendations import _build_category_recommendations
from app.place_candidate_search_service import (
    CandidateSearchResult,
    CategoryMatchStatus,
    FeatureEvidenceStatus,
    KakaoPlaceCandidate,
    PlaceCandidateEvidence,
    PlaceCategoryClassification,
    ProviderStatus,
)
from app.record_preference_analysis import (
    EvidenceStatus,
    FacetTargetKind,
    PlaceType,
    PreferenceFacet,
    RecordPreferenceAnalysis,
    RecordPreferenceAnalysisResponse,
    RecommendationCategory,
)


def test_tie_break_prefers_facet_search_provenance_without_changing_score_or_evidence():
    analyses = RecordPreferenceAnalysisResponse(analyses=[RecordPreferenceAnalysis(
        record_id=7,
        place_name="Synthetic cafe",
        place_type=PlaceType.CAFE,
        categories=[RecommendationCategory.CAFE],
        emotion="LOVE",
        emotion_intensity=1.0,
        evidence_status=EvidenceStatus.VERIFIED,
        facets=[PreferenceFacet(
            target_kind=FacetTargetKind.SPACE,
            target_text="indoor space",
            features=["quiet"],
            categories=[RecommendationCategory.CAFE],
            polarity="liked",
            evidence="synthetic local fixture",
            confidence=0.95,
        )],
    )])

    def candidate(place_id, name, priority):
        place = KakaoPlaceCandidate(
            kakao_place_id=str(place_id),
            place_name=name,
            address="Gwangju Dong-gu",
            latitude=35.15,
            longitude=126.92,
            category_group_code="CE7",
            category_name="cafe",
            place_url=f"https://place.map.kakao.com/{place_id}",
        )
        return PlaceCandidateEvidence(
            place=place,
            classification=PlaceCategoryClassification(
                requested_category=RecommendationCategory.ALL,
                categories=[RecommendationCategory.CAFE],
                status=CategoryMatchStatus.CONFIRMED,
                evidence=["synthetic Kakao category"],
            ),
            preference_evidence=[],
            feature_search_status=FeatureEvidenceStatus.UNAVAILABLE,
            search_query_priority=priority,
        )

    result = CandidateSearchResult(
        category=RecommendationCategory.ALL,
        region="Gwangju",
        kakao_status=ProviderStatus.COMPLETE,
        tavily_status=ProviderStatus.UNAVAILABLE,
        kakao_call_count=2,
        tavily_call_count=0,
        candidates=[
            candidate(1, "A Alphabetically First", 1),
            candidate(2, "Z Strong Query Match", 6),
        ],
    )

    ranked = _build_category_recommendations(result, analyses, RecommendationCategory.ALL)

    assert [item.kakao_place_id for item in ranked] == ["2", "1"]
    assert ranked[0].match_score == ranked[1].match_score
    assert ranked[0].matched_keywords == ranked[1].matched_keywords == []
    assert ranked[0].match_score <= 0.30
