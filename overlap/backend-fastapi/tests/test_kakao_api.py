import httpx
import pytest

from app import kakao


def test_search_places_logs_only_status_and_raw_count(monkeypatch, caplog):
    monkeypatch.setattr(kakao, "KAKAO_REST_API_KEY", "test-only-key")
    monkeypatch.setattr(
        kakao.httpx,
        "get",
        lambda *args, **kwargs: httpx.Response(
            200,
            request=httpx.Request("GET", "https://example.test"),
            json={"documents": [{
                "id": "123", "place_name": "사직공원", "road_address_name": "광주 남구",
                "address_name": "광주 남구", "x": "126.91", "y": "35.14",
                "place_url": "https://place.map.kakao.com/123", "category_name": "여행 > 공원",
            }]},
        ),
    )
    caplog.set_level("INFO", logger="uvicorn.error")

    result = kakao.search_places("민감한 검색어")

    assert len(result) == 1
    assert result[0]["category_name"] == "여행 > 공원"
    assert "http_status=200 raw_result_count=1" in caplog.text
    assert "민감한 검색어" not in caplog.text
    assert "test-only-key" not in caplog.text


def test_search_places_reports_http_failure_without_logging_response_body(monkeypatch, caplog):
    monkeypatch.setattr(kakao, "KAKAO_REST_API_KEY", "test-only-key")
    monkeypatch.setattr(
        kakao.httpx,
        "get",
        lambda *args, **kwargs: httpx.Response(
            401,
            request=httpx.Request("GET", "https://example.test"),
            json={"message": "sensitive provider body"},
        ),
    )
    caplog.set_level("INFO", logger="uvicorn.error")

    with pytest.raises(httpx.HTTPStatusError):
        kakao.search_places("검색어")

    assert "http_status=401 raw_result_count=unavailable" in caplog.text
    assert "sensitive provider body" not in caplog.text
    assert "검색어" not in caplog.text
