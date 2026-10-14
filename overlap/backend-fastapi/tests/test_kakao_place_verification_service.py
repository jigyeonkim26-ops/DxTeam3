from app.ai_recommendation_models import PlaceCandidate, PlaceCandidateResponse, PreferenceKeyword
from app.kakao_place_verification_service import KakaoPlaceVerificationService
from app.recommendation_record_adapter import RecommendationEmotionCode, RecommendationRecord


def record(place_name="사직공원", place_id="111"):
    return RecommendationRecord(
        record_id=1, user_id=1, place_id=1, kakao_place_id=place_id,
        place_name=place_name, address="광주광역시 남구 사직길", content="조용한 산책",
        emotion_code=RecommendationEmotionCode.LOVE, emotion_meaning="최고",
    )


def place(place_id, name, address="광주광역시 남구", latitude=35.14):
    return {
        "kakao_place_id": place_id, "name": name, "address": address,
        "latitude": latitude, "longitude": 126.91,
        "place_url": f"https://place.map.kakao.com/{place_id}",
        "category_name": "",
    }


def hints(*names):
    return PlaceCandidateResponse(candidates=[
        PlaceCandidate(name=name, summary="조용한 산책", source_url=f"https://web.test/{index}")
        for index, name in enumerate(names)
    ])


KEYWORDS = [PreferenceKeyword(keyword="산책", score=0.9)]


def test_web_article_is_rejected_and_only_exact_region_matched_poi_is_used():
    queries = []

    def search(query):
        queries.append(query)
        if "광암교" in query:
            return [place("999", "광암교", "경기도 광주시"),
                    place("888", "광암교", latitude=91), place("222", "광암교")]
        if "관광명소 추천" in query:
            return [place("888", "사직공원"), place("777", "양림동")]
        return []

    result = KakaoPlaceVerificationService(search=search).verify(
        hints("광주시 야간 관광명소 추천", "광암교"), KEYWORDS, [record()]
    )
    assert [item.name for item in result.candidates] == ["광암교"]
    assert result.candidates[0].kakao_place_id == "222"
    assert result.candidates[0].latitude == 35.14
    assert all(query.startswith("광주광역시 ") for query in queries)


def test_visited_ids_and_duplicate_kakao_ids_are_removed():
    def search(query):
        if "광암교" in query:
            return [place("111", "광암교"), place("222", "광암교")]
        if "산책" in query:
            return [place("222", "광암교"), place("333", "양림동")]
        return []

    result = KakaoPlaceVerificationService(search=search).verify(
        hints("광암교"), KEYWORDS, [record(place_name="다른 방문 장소")]
    )
    assert [item.kakao_place_id for item in result.candidates] == ["222", "333"]


def test_direct_kakao_fallback_returns_only_verified_places_without_padding():
    calls = []

    def search(query):
        calls.append(query)
        return [{**place("444", "양림동 펭귄마을"), "category_name": "여행 > 공원"}] if query == "광주광역시 산책" else []

    result = KakaoPlaceVerificationService(search=search).verify(hints(), KEYWORDS, [record()])
    assert [item.name for item in result.candidates] == ["양림동 펭귄마을"]
    assert result.candidates[0].summary == "Kakao Local category: 여행 > 공원"
    assert len(calls) <= KakaoPlaceVerificationService.MAX_FALLBACK_KEYWORDS


def test_kakao_calls_are_bounded_even_with_many_hints():
    calls = []
    service = KakaoPlaceVerificationService(search=lambda query: calls.append(query) or [])
    service.verify(hints(*(f"후보{i}" for i in range(10))), KEYWORDS, [record()])
    assert len(calls) <= service.MAX_CALLS


def test_region_alias_and_explicit_locality_prefix_are_normalized_without_branch_fuzzing():
    def search(query):
        if "강남점" in query:
            return [place("556", "사직공원 강남점", "광주 남구")]
        if "사직공원" in query:
            return [place("555", "사직공원", "광주 남구", latitude=35.15)]
        return []

    result = KakaoPlaceVerificationService(search=search).verify(
        hints("광주 사직공원", "사직공원 홍대점"), KEYWORDS, [record(place_name="양림동")]
    )
    assert [(item.kakao_place_id, item.name, item.address, item.latitude) for item in result.candidates] == [
        ("555", "사직공원", "광주 남구", 35.15),
    ]


def test_rejection_counts_explain_zero_verified_results_without_logging_search_terms(caplog):
    def search(query):
        if "찾을수없는후보" not in query:
            return []
        return [
            {**place("bad-id", "찾을수없는후보"), "kakao_place_id": "bad-id"},
            {**place("222", "찾을수없는후보"), "latitude": 91},
            place("333", "찾을수없는후보", "경기도 성남시"),
            place("111", "찾을수없는후보"),
            place("444", "방문 장소"),
            place("555", "다른 장소"),
        ]

    caplog.set_level("INFO", logger="uvicorn.error")
    result = KakaoPlaceVerificationService(search=search).verify(
        hints("찾을수없는후보"), KEYWORDS,
        [record(place_name="방문 장소", place_id="111")],
    )

    assert result.candidates == []
    assert "raw_results=6" in caplog.text
    assert "invalid_place_ids=1" in caplog.text
    assert "invalid_coordinates=1" in caplog.text
    assert "region_mismatch=1" in caplog.text
    assert "place_name_mismatch=1" in caplog.text
    assert "visited_ids=1" in caplog.text
    assert "visited_names=1" in caplog.text
    assert "verified=0" in caplog.text
    assert "찾을수없는후보" not in caplog.text
