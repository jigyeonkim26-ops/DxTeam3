import httpx

from app import kakao
from app.place_candidate_search_service import (
    CategoryMatchStatus,
    FeatureEvidenceStatus,
    KakaoCategoryClassifier,
    KakaoPlaceCandidate,
    PlaceCandidateSearchService,
    ProviderStatus,
)
from app.record_preference_analysis import (
    EvidenceStatus,
    FacetTargetKind,
    PlaceType,
    PreferenceFacet,
    RecommendationCategory,
    RecordPreferenceAnalysis,
)
from app.recommendation_record_adapter import RecommendationEmotionCode


def kakao_place(place_id="100", name="다정한 카페", address="광주광역시 서구 상무대로", *,
                code="CE7", category="카페 > 커피전문점", lat="35.15", lon="126.85"):
    return {
        "id": place_id,
        "place_name": name,
        "road_address_name": address,
        "address_name": address,
        "x": lon,
        "y": lat,
        "category_group_code": code,
        "category_name": category,
        "place_url": f"https://place.map.kakao.com/{place_id}",
    }


def cafe_preference(record_id=1, target="매장", features=("조용하고", "넓고")):
    facet = PreferenceFacet(
        target_kind=FacetTargetKind.SPACE,
        target_text=target,
        features=list(features),
        categories=[RecommendationCategory.CAFE],
        polarity="liked",
        evidence="매장이 조용하고 넓고 좋았다.",
        confidence=0.9,
    )
    return RecordPreferenceAnalysis(
        record_id=record_id,
        place_name="카페 온도",
        place_type=PlaceType.CAFE,
        place_type_label="카페",
        place_type_evidence="Kakao category",
        categories=[RecommendationCategory.CAFE],
        emotion=RecommendationEmotionCode.LIKE,
        emotion_intensity=0.8,
        facets=[facet],
        evidence_status=EvidenceStatus.VERIFIED,
    )


def bar_preference():
    facet = PreferenceFacet(
        target_kind=FacetTargetKind.DRINK,
        target_text="유자하이볼",
        features=["맛있었다"],
        categories=[RecommendationCategory.BAR],
        polarity="liked",
        evidence="유자하이볼이 맛있었다.",
        confidence=0.9,
    )
    return RecordPreferenceAnalysis(
        record_id=2,
        place_name="유자 이자카야",
        place_type=PlaceType.BAR,
        place_type_label="이자카야",
        place_type_evidence="Kakao category",
        categories=[RecommendationCategory.BAR, RecommendationCategory.FOOD],
        emotion=RecommendationEmotionCode.LOVE,
        emotion_intensity=1,
        facets=[facet],
        evidence_status=EvidenceStatus.VERIFIED,
    )


def service(kakao, tavily=None, *, kakao_key="kakao-test", tavily_key="tavily-test", clock=None):
    kwargs = {
        "kakao_search": kakao,
        "kakao_api_key": kakao_key,
        "tavily_api_key": tavily_key,
        "tavily_post_json": tavily or (lambda *a, **k: None),
    }
    if clock:
        kwargs["clock"] = clock
    return PlaceCandidateSearchService(**kwargs)


def tavily_response(results):
    class Response:
        def raise_for_status(self):
            pass

        def json(self):
            return {"results": results}

    return Response()


def test_kakao_raw_response_mapping_preserves_category_fields():
    place = KakaoPlaceCandidate.from_kakao_result(kakao_place())

    assert place.kakao_place_id == "100"
    assert place.place_name == "다정한 카페"
    assert place.address == "광주광역시 서구 상무대로"
    assert place.latitude == 35.15
    assert place.longitude == 126.85
    assert place.category_group_code == "CE7"
    assert place.category_name == "카페 > 커피전문점"
    assert place.place_url.endswith("/100")


def test_existing_kakao_search_helper_adds_category_code_without_removing_legacy_fields(monkeypatch):
    monkeypatch.setattr(kakao, "KAKAO_REST_API_KEY", "test-key")
    monkeypatch.setattr(kakao.httpx, "get", lambda *args, **kwargs: httpx.Response(
        200,
        request=httpx.Request("GET", "https://dapi.kakao.com/v2/local/search/keyword.json"),
        json={"documents": [kakao_place()]},
    ))

    result = kakao.search_places("광주 카페")

    assert result[0]["kakao_place_id"] == "100"
    assert result[0]["name"] == "다정한 카페"
    assert result[0]["category_group_code"] == "CE7"
    assert result[0]["category_name"] == "카페 > 커피전문점"
    assert result[0]["place_url"].endswith("/100")


def test_kakao_legacy_helper_fields_are_accepted_with_missing_category_unknown():
    place = KakaoPlaceCandidate.from_kakao_result({
        "kakao_place_id": "101", "name": "이름", "address": "광주 서구",
        "latitude": 35.1, "longitude": 126.8, "place_url": "https://place.map.kakao.com/101",
    })
    classification = KakaoCategoryClassifier.classify(place, "cafe")

    assert place.category_group_code is None
    assert classification.status == CategoryMatchStatus.VERIFICATION_REQUIRED


def test_invalid_kakao_place_id_or_coordinates_are_rejected():
    invalid_id = kakao_place("not-an-id")
    invalid_coord = kakao_place("102", lat="91")
    result = service(lambda query, **kwargs: [invalid_id, invalid_coord]).search(
        category="cafe", region="광주", preferences=[cafe_preference()]
    )
    assert result.candidates == []


def test_cafe_candidate_is_kept_and_parking_is_rejected():
    cafe = KakaoPlaceCandidate.from_kakao_result(kakao_place())
    parking = KakaoPlaceCandidate.from_kakao_result(kakao_place(
        "200", "서구 공영주차장", code="PK6", category="교통,수송 > 교통시설 > 주차장",
    ))
    assert KakaoCategoryClassifier.classify(cafe, "cafe").status == CategoryMatchStatus.CONFIRMED
    assert KakaoCategoryClassifier.classify(parking, "cafe").status == CategoryMatchStatus.MISMATCH

    result = service(lambda query, **kwargs: [kakao_place(), kakao_place(
        "200", "서구 공영주차장", code="PK6", category="교통,수송 > 교통시설 > 주차장",
    )]).search(category="cafe", region="광주", preferences=[cafe_preference()])
    assert [item.place.kakao_place_id for item in result.candidates] == ["100"]


def test_izakaya_is_bar_and_food_but_generic_food_group_needs_review_for_bar():
    izakaya = KakaoPlaceCandidate.from_kakao_result(kakao_place(
        "300", "유자 이자카야", code="FD6", category="음식점 > 술집 > 이자카야",
    ))
    general_food = KakaoPlaceCandidate.from_kakao_result(kakao_place(
        "301", "다정한 식당", code="FD6", category="음식점 > 한식",
    ))

    bar_result = KakaoCategoryClassifier.classify(izakaya, "bar")
    assert bar_result.status == CategoryMatchStatus.CONFIRMED
    assert set(bar_result.categories) == {RecommendationCategory.BAR, RecommendationCategory.FOOD}
    assert KakaoCategoryClassifier.classify(general_food, "bar").status == CategoryMatchStatus.VERIFICATION_REQUIRED
    assert KakaoCategoryClassifier.classify(general_food, "food").status == CategoryMatchStatus.CONFIRMED


def test_nature_and_activity_require_specific_subcategory_not_broad_group_alone():
    park = KakaoPlaceCandidate.from_kakao_result(kakao_place(
        "400", "상무공원", code="AT4", category="여행 > 관광,명소 > 공원",
    ))
    broad_attraction = KakaoPlaceCandidate.from_kakao_result(kakao_place(
        "401", "광주 명소", code="AT4", category="여행 > 관광,명소",
    ))
    stadium = KakaoPlaceCandidate.from_kakao_result(kakao_place(
        "402", "광주 야구장", code="CT1", category="문화,예술 > 스포츠시설 > 야구장",
    ))

    assert KakaoCategoryClassifier.classify(park, "nature").status == CategoryMatchStatus.CONFIRMED
    assert KakaoCategoryClassifier.classify(broad_attraction, "nature").status == CategoryMatchStatus.VERIFICATION_REQUIRED
    assert KakaoCategoryClassifier.classify(stadium, "activity").status == CategoryMatchStatus.CONFIRMED


def test_kakao_query_uses_region_specific_context_and_progressive_broadening():
    queries = []

    def search(query, **kwargs):
        queries.append(query)
        if "유자하이볼" in query:
            return []
        if "하이볼" in query:
            return []
        if "이자카야" in query:
            return [kakao_place("310", "광주 유자 이자카야", address="광주광역시 서구 상무대로", code="FD6", category="음식점 > 술집 > 이자카야")]
        return []

    result = service(search).search(category="bar", region="광주", preferences=[bar_preference()])

    assert queries[0] == "광주 유자하이볼 이자카야"
    assert queries[1] == "광주 하이볼 이자카야"
    assert any(query == "광주 이자카야" for query in queries)
    assert all(query.startswith("광주 ") for query in queries)
    assert result.candidates[0].classification.status == CategoryMatchStatus.CONFIRMED
    assert result.kakao_call_count <= 6


def test_duplicate_queries_names_and_kakao_ids_are_deduplicated():
    calls = []

    def search(query, **kwargs):
        calls.append(query)
        return [
            kakao_place("500", "다정한 카페"),
            kakao_place("501", "다정한 카페"),  # duplicate normalized name
            kakao_place("500", "다른 카페 이름"),  # duplicate Kakao ID
        ]

    result = service(search).search(category="cafe", region="광주", preferences=[cafe_preference()])

    assert len(result.candidates) == 1
    assert result.candidates[0].place.kakao_place_id == "500"
    assert len(calls) == 3  # One unique candidate remains below the three-place target, so bounded broadening continues.


def test_visited_place_id_and_name_are_excluded():
    result = service(lambda query, **kwargs: [kakao_place("600", "다정한 카페"), kakao_place("601", "새 카페")]).search(
        category="cafe", region="광주", preferences=[cafe_preference()],
        visited_place_ids={"600"}, visited_place_names={"새 카페"},
    )
    assert result.candidates == []
    assert result.kakao_status == ProviderStatus.NO_RESULTS


def test_mixed_gwangju_daegu_results_never_cross_explicit_region():
    calls = []

    def search(query, **kwargs):
        calls.append(query)
        return [kakao_place("700", "광주 카페", address="광주광역시 서구 상무대로"),
                kakao_place("701", "대구 카페", address="대구광역시 중구 동성로")]

    result = service(search).search(category="cafe", region="대구", preferences=[cafe_preference()])

    assert all(query.startswith("대구 ") for query in calls)
    assert [item.place.kakao_place_id for item in result.candidates] == ["701"]


def test_zero_exact_kakao_results_expand_to_general_category_query():
    queries = []

    def search(query, **kwargs):
        queries.append(query)
        if query == "광주 넓은 카페":
            return []
        if query == "광주 조용한 카페":
            return []
        if query == "광주 카페":
            return [kakao_place("800", "일반 카페")]
        return []

    result = service(search).search(category="cafe", region="광주", preferences=[cafe_preference()])
    assert queries[:3] == ["광주 넓은 카페", "광주 조용한 카페", "광주 카페"]
    assert [item.place.kakao_place_id for item in result.candidates] == ["800"]


def test_tavily_feature_evidence_requires_same_place_region_and_district():
    tavily_calls = []

    def tavily(url, **kwargs):
        tavily_calls.append(kwargs)
        return tavily_response([
            {"title": "다정한 카페 광주 동구", "content": "다정한 카페에 조용한 좌석이 있습니다.", "url": "https://blog.example/wrong-branch"},
            {"title": "다정한 카페 광주 서구", "content": "다정한 카페 광주 서구는 조용하고 넓은 좌석이 있습니다.", "url": "https://blog.example/right"},
        ])

    result = service(lambda query, **kwargs: [kakao_place()], tavily).search(
        category="cafe", region="광주", preferences=[cafe_preference()],
    )
    candidate = result.candidates[0]
    confirmed = [item for item in candidate.preference_evidence if item.status == FeatureEvidenceStatus.CONFIRMED]

    assert len(tavily_calls) == 1
    assert all(item.evidence_url == "https://blog.example/right" for item in confirmed)
    assert {item.preference for item in confirmed} == {"조용하고", "넓고"}
    assert "https://blog.example/wrong-branch" not in str(confirmed)


def test_tavily_is_called_for_verified_facets_but_stays_within_three_place_budget():
    tavily_queries = []

    def kakao(query, **kwargs):
        return [kakao_place(str(1200 + i), f"Synthetic Cafe {i}") for i in range(11)]

    def tavily(url, **kwargs):
        query = kwargs["json"]["query"]
        tavily_queries.append(query)
        return tavily_response([{
            "title": query,
            "content": query + " 조용하고 넓은 실내 공간을 소개합니다.",
            "url": "https://example.test/synthetic-cafe",
        }])

    result = service(kakao, tavily).search(
        category="cafe", region="광주광역시", preferences=[cafe_preference()],
    )

    assert len(result.candidates) == 11
    assert 0 < len(tavily_queries) <= 3
    assert result.tavily_call_count == len(tavily_queries)


def test_tavily_budget_samples_candidates_from_distinct_kakao_queries():
    query_index = [0]
    tavily_names = []

    def kakao(query, **kwargs):
        query_index[0] += 1
        return [kakao_place(str(1450 + query_index[0]), f"광주 후보 카페 {query_index[0]}")]

    def tavily(url, **kwargs):
        tavily_names.append(kwargs["json"]["query"].split(" 광주 ")[0])
        return tavily_response([])

    result = service(kakao, tavily).search(
        category="cafe", region="광주", preferences=[cafe_preference()]
    )

    assert len(result.candidates) >= 3
    assert len(tavily_names) == 3
    assert len(set(tavily_names)) == 3


def test_region_leading_whitespace_is_normalized_before_query_and_candidate_check():
    queries = []
    result = service(
        lambda query, **kwargs: queries.append(query) or [kakao_place()],
    ).search(category="cafe", region="  광주광역시  ", preferences=[cafe_preference()])

    assert result.region == "광주광역시"
    assert queries and all(query.startswith("광주 ") for query in queries)
    assert result.candidates


def test_inferred_second_level_region_prevents_cross_city_candidates():
    query_region = "전남광주통합특별시 광산구"
    result = service(lambda query, **kwargs: [
        kakao_place("1801", "광산구 synthetic cafe", f"{query_region} 월계동"),
        kakao_place("1802", "여수 synthetic cafe", "전남광주통합특별시 여수시 학동"),
    ]).search(category="cafe", region=query_region, preferences=[cafe_preference()])

    assert [item.place.kakao_place_id for item in result.candidates] == ["1801"]
    assert result.region == query_region


def test_insufficient_tavily_evidence_keeps_kakao_place_without_personalized_claim():
    result = service(
        lambda query, **kwargs: [kakao_place()],
        lambda *args, **kwargs: tavily_response([{"title": "다정한 카페 광주 서구", "content": "영업 정보입니다.", "url": "https://blog.example/info"}]),
    ).search(category="cafe", region="광주", preferences=[cafe_preference()])

    assert len(result.candidates) == 1
    assert result.candidates[0].place.kakao_place_id == "100"
    assert result.candidates[0].feature_search_status == FeatureEvidenceStatus.INSUFFICIENT
    assert all(item.evidence_url is None for item in result.candidates[0].preference_evidence)


def test_tavily_failure_or_timeout_does_not_remove_real_kakao_candidate():
    def fail(*args, **kwargs):
        raise httpx.ReadTimeout("slow")

    result = service(lambda query, **kwargs: [kakao_place()], fail).search(
        category="cafe", region="광주", preferences=[cafe_preference()],
    )
    assert len(result.candidates) == 1
    assert result.kakao_status == ProviderStatus.COMPLETE
    assert result.tavily_status == ProviderStatus.UNAVAILABLE
    assert result.candidates[0].feature_search_status == FeatureEvidenceStatus.UNAVAILABLE


def test_kakao_timeout_reports_unavailable_without_tavily_calls():
    def fail(query, **kwargs):
        raise httpx.ReadTimeout("slow")

    result = service(fail).search(category="cafe", region="광주", preferences=[cafe_preference()])
    assert result.kakao_status == ProviderStatus.UNAVAILABLE
    assert result.kakao_call_count == 1
    assert result.tavily_call_count == 0
    assert result.candidates == []


def test_tavily_not_called_when_category_is_only_verification_required():
    calls = []
    result = service(
        lambda query, **kwargs: [kakao_place("901", "광주 음식점", code="FD6", category="음식점")],
        lambda *args, **kwargs: calls.append(args) or tavily_response([]),
    ).search(category="bar", region="광주", preferences=[bar_preference()])

    assert result.candidates[0].classification.status == CategoryMatchStatus.VERIFICATION_REQUIRED
    assert result.candidates[0].feature_search_status == FeatureEvidenceStatus.SKIPPED
    assert calls == []


def test_search_consumes_stage1_record_facet_without_flattening_target_context():
    queries = []

    def search(query, **kwargs):
        queries.append(query)
        if "유자하이볼" in query:
            return [kakao_place("990", "광주 유자 이자카야", code="FD6", category="음식점 > 술집 > 이자카야")]
        return []

    result = service(search).search(category="bar", region="광주", preferences=[bar_preference()])

    assert queries[0] == "광주 유자하이볼 이자카야"
    assert result.candidates[0].place.category_name == "음식점 > 술집 > 이자카야"
    assert result.candidates[0].classification.status == CategoryMatchStatus.CONFIRMED


def test_all_category_search_prioritizes_stronger_specific_preference_not_record_order():
    strong_bar = bar_preference()
    weak_cafe = cafe_preference().model_copy(update={"emotion_intensity": 0.15})

    queries = PlaceCandidateSearchService._build_queries(
        RecommendationCategory.ALL, "광주", [weak_cafe, strong_bar]
    )

    assert queries[0].startswith("광주 ")
    assert "유자하이볼" in queries[0]
    assert "이자카야" in queries[0]
    assert len(queries) <= PlaceCandidateSearchService.MAX_KAKAO_CALLS


def test_all_search_spreads_six_call_budget_across_distinct_preferences_and_normalizes_region():
    yuzu = bar_preference()
    # The same record also mentions the shorter highball form; it should not
    # consume a second slot when the exact yuzu-highball intent is present.
    duplicate = yuzu.model_copy(update={
        "facets": [*yuzu.facets,
                   yuzu.facets[0].model_copy(update={"target_text": "하이볼"}),
                   yuzu.facets[0].model_copy(update={"target_text": "꼬치"})]
    })
    cafe = cafe_preference(record_id=3).model_copy(update={"emotion_intensity": 0.8})
    activity = RecordPreferenceAnalysis(
        record_id=4, place_name="대구실내체육관", place_type=PlaceType.ACTIVITY,
        categories=[RecommendationCategory.ACTIVITY], emotion=RecommendationEmotionCode.LOVE,
        emotion_intensity=0.75, evidence_status=EvidenceStatus.VERIFIED,
        facets=[PreferenceFacet(target_kind=FacetTargetKind.ACTIVITY, target_text="농구 경기",
                                features=["홈 개막전 이벤트"], categories=[RecommendationCategory.ACTIVITY],
                                polarity="liked", evidence="농구 경기가 즐거웠다.", confidence=0.9)],
    )

    queries = PlaceCandidateSearchService._build_queries(
        RecommendationCategory.ALL, "전남광주통합특별시 동구", [duplicate, cafe, activity]
    )

    assert len(queries) <= PlaceCandidateSearchService.MAX_KAKAO_CALLS == 6
    assert queries[0].startswith("광주 동구 ")
    assert sum(len(query.split()) >= 2 and query.split()[-2] == "하이볼" for query in queries) == 0
    assert any("꼬치" in query for query in queries)
    assert any("카페" in query for query in queries)
    assert any("농구 경기" in query for query in queries)


def test_analysis_failure_type_only_fallback_builds_queries_for_all_and_nature():
    from app.place_candidate_search_service import KakaoPlaceCandidate, CategoryMatchStatus
    from app.record_preference_analysis import EvidenceStatus

    nature_only = RecordPreferenceAnalysis(
        record_id=1, place_name="무등산 공원", place_type=PlaceType.NATURE,
        place_type_label="공원", place_type_evidence="place_name_hint",
        categories=[RecommendationCategory.NATURE], emotion=RecommendationEmotionCode.LOVE,
        emotion_intensity=1.0, facets=[], evidence_status=EvidenceStatus.UNAVAILABLE,
    )
    calls = []

    def kakao(query, **kwargs):
        calls.append(query)
        return [kakao_place("771", "광주 공원", code="AT4", category="여행 > 공원")]

    for category in (RecommendationCategory.ALL, RecommendationCategory.NATURE):
        calls.clear()
        result = service(kakao).search(category=category, region="광주광역시", preferences=[nature_only])
        assert calls
        assert result.query_count > 0
        assert result.kakao_call_count > 0
        assert result.kakao_status == ProviderStatus.COMPLETE
        assert all(query.startswith("광주 ") for query in calls)


def test_unknown_without_category_or_facets_is_classified_as_no_safe_query():
    from app.record_preference_analysis import EvidenceStatus

    unknown = RecordPreferenceAnalysis(
        record_id=1, place_name="장소", place_type=PlaceType.UNKNOWN,
        categories=[], emotion=RecommendationEmotionCode.LOVE, emotion_intensity=1.0,
        facets=[], evidence_status=EvidenceStatus.UNAVAILABLE,
    )
    calls = []
    result = service(lambda query, **kwargs: calls.append(query) or []).search(
        category="all", region="광주", preferences=[unknown]
    )

    assert result.query_count == 0
    assert result.search_skip_reason == "no_supported_preference_query"
    assert result.kakao_call_count == 0
    assert calls == []


def test_empty_kakao_cache_is_observable_and_short_lived():
    now = [100.0]
    calls = []
    search = service(lambda query, **kwargs: calls.append(query) or [], clock=lambda: now[0])

    first = search.search(category="cafe", region="광주", preferences=[cafe_preference()])
    second = search.search(category="cafe", region="광주", preferences=[cafe_preference()])
    assert first.kakao_call_count > 0
    assert second.kakao_call_count == 0
    assert second.kakao_empty_cache_hit_count == second.query_count
    assert second.search_skip_reason == "cached_empty_kakao_results"

    now[0] += 31
    third = search.search(category="cafe", region="광주", preferences=[cafe_preference()])
    assert third.kakao_call_count > 0
    assert len(calls) > first.kakao_call_count


def test_successful_kakao_zero_results_are_distinct_from_skipped_search():
    from app.record_preference_analysis import EvidenceStatus
    nature = RecordPreferenceAnalysis(
        record_id=1, place_name="무등산 공원", place_type=PlaceType.NATURE,
        categories=[RecommendationCategory.NATURE], emotion=RecommendationEmotionCode.LOVE,
        emotion_intensity=1.0, facets=[], evidence_status=EvidenceStatus.PARTIAL,
    )
    result = service(lambda query, **kwargs: []).search(
        category="nature", region="광주", preferences=[nature]
    )
    assert result.query_count > 0
    assert result.kakao_call_count > 0
    assert result.search_skip_reason == "kakao_returned_no_candidates"
    assert result.kakao_status == ProviderStatus.NO_RESULTS


def test_identical_kakao_and_tavily_lookups_use_short_lived_cache():
    clock = [100.0]
    kakao_calls = []
    tavily_calls = []

    def kakao(query, **kwargs):
        kakao_calls.append(query)
        return [kakao_place()]

    def tavily(url, **kwargs):
        tavily_calls.append(kwargs["json"]["query"])
        return tavily_response([{"title": "다정한 카페 광주 서구", "content": "조용하고 넓은 카페입니다.", "url": "https://blog.example/cafe"}])

    subject = service(kakao, tavily, clock=lambda: clock[0])
    for _ in range(2):
        subject.search(category="cafe", region="광주", preferences=[cafe_preference()])

    assert len(kakao_calls) == 3
    assert len(tavily_calls) == 1


def test_missing_kakao_or_tavily_configuration_fails_closed_without_losing_place():
    no_kakao = service(lambda *a, **k: [], kakao_key="")
    missing = no_kakao.search(category="cafe", region="광주", preferences=[cafe_preference()])
    assert missing.kakao_status == ProviderStatus.UNAVAILABLE

    no_tavily = service(lambda query, **kwargs: [kakao_place()], tavily_key="")
    result = no_tavily.search(category="cafe", region="광주", preferences=[cafe_preference()])
    assert len(result.candidates) == 1
    assert result.candidates[0].feature_search_status == FeatureEvidenceStatus.UNAVAILABLE


def test_all_category_with_no_structured_domain_does_not_fan_out_to_every_place_type():
    calls = []
    result = service(lambda query, **kwargs: calls.append(query) or []).search(
        category="all", region="광주", preferences=[]
    )
    assert result.kakao_status == ProviderStatus.NO_RESULTS
    assert result.kakao_call_count == 0
    assert calls == []



def test_tavily_budget_prefers_candidates_from_strong_facet_queries():
    tavily_queries = []
    strong = kakao_place(
        "9901", "Z Strong Facet Izakaya", "\uad11\uc8fc\uad11\uc5ed\uc2dc \ub3d9\uad6c \uc11c\uc11d\ub85c",
        code="FD6", category="\uc74c\uc2dd\uc810 > \uc220\uc9d1 > \uc774\uc790\uce74\uc57c",
    )
    broad = [
        kakao_place(f"991{i}", f"A Broad Candidate {i}", "\uad11\uc8fc\uad11\uc5ed\uc2dc \ub3d9\uad6c \ucda9\uc7a5\ub85c",
                    code="FD6", category="\uc74c\uc2dd\uc810 > \uc220\uc9d1 > \ud3ec\ucc28")
        for i in range(3)
    ]

    def kakao(query, **kwargs):
        if "\uc720\uc790\ud558\uc774\ubcfc" in query:
            return [strong]
        if query.endswith("\uc774\uc790\uce74\uc57c"):
            return broad
        return []

    def tavily(url, **kwargs):
        tavily_queries.append(kwargs["json"]["query"])
        return tavily_response([])

    result = service(kakao, tavily).search(
        category="bar", region="\uad11\uc8fc", preferences=[bar_preference()],
    )

    selected_strong = any(query.startswith("Z Strong Facet Izakaya ") for query in tavily_queries)
    strong_candidate = next(item for item in result.candidates if item.place.kakao_place_id == "9901")
    assert len(result.candidates) == 4
    assert len(tavily_queries) == 3
    assert selected_strong
    assert strong_candidate.search_query_priority > min(
        item.search_query_priority for item in result.candidates if item.place.kakao_place_id != "9901"
    )


def test_merged_gwangju_region_and_korean_feature_variants_keep_identity_boundary():
    from app.record_preference_analysis import RecommendationCategory, RecordPreferenceAnalysis
    from app.recommendation_record_adapter import RecommendationEmotionCode

    region = "\uc804\ub0a8\uad11\uc8fc\ud1b5\ud569\ud2b9\ubcc4\uc2dc \ub3d9\uad6c"
    content = "\ub9e4\uc7a5\uc774 \ub113\uace0 \uc870\uc6a9\ud574\uc11c \uc88b\uc558\ub2e4."
    record = RecordPreferenceAnalysis(
        record_id=881, place_name="\uce74\ud398 \uae30\ub85d", place_type=PlaceType.CAFE,
        categories=[RecommendationCategory.CAFE], emotion=RecommendationEmotionCode.LIKE,
        emotion_intensity=1.0, evidence_status=EvidenceStatus.VERIFIED,
        facets=[PreferenceFacet(
            target_kind=FacetTargetKind.SPACE, target_text="\ub9e4\uc7a5",
            features=["\ub113\uace0", "\uc870\uc6a9\ud574\uc11c"],
            categories=[RecommendationCategory.CAFE], polarity="liked", evidence=content, confidence=0.95,
        )],
    )
    place = kakao_place(
        "1881", "CafeOasis", region + " \uc11c\uc11d\ub85c",
        category="\uc74c\uc2dd\uc810 > \uce74\ud398", code="CE7",
    )
    tavily_calls = []

    def tavily(url, **kwargs):
        tavily_calls.append(kwargs["json"]["query"])
        return tavily_response([
            {"title": "CafeOasis \uad11\uc8fc \uc11c\uad6c", "content": "CafeOasis \uad11\uc8fc \uc11c\uad6c \ub113\uc740 \uc2e4\ub0b4\uc640 \uc870\uc6a9\ud55c \ubd84\uc704\uae30", "url": "https://example.test/wrong-district"},
            {"title": "CafeOasis \uad11\uc8fc \ub3d9\uad6c", "content": "CafeOasis \uad11\uc8fc \ub3d9\uad6c\uc758 \ub113\uc740 \uc2e4\ub0b4\uc640 \uc870\uc6a9\ud55c \ubd84\uc704\uae30", "url": "https://example.test/right-district"},
        ])

    result = service(lambda query, **kwargs: [place], tavily).search(
        category="cafe", region=region, preferences=[record],
    )
    candidate = result.candidates[0]
    confirmed = [row for row in candidate.preference_evidence if row.status == FeatureEvidenceStatus.CONFIRMED]

    assert result.candidates
    assert len(tavily_calls) == 1
    assert {row.preference for row in confirmed} == {"\ub113\uace0", "\uc870\uc6a9\ud574\uc11c"}
    assert {row.evidence_url for row in confirmed} == {"https://example.test/right-district"}
    assert all("wrong-district" not in (row.evidence_url or "") for row in confirmed)
