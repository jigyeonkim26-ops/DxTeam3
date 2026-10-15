import httpx
import pytest
import json

from app import kakao
from app import recommendation_diagnostics as diagnostics


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
def test_kakao_http_status_and_successful_empty_response_are_separate_diagnostic_counts(tmp_path, monkeypatch):
    monkeypatch.setenv("OVERLAP_ENV", "development")
    monkeypatch.setenv("OVERLAP_AI_DIAGNOSTICS", "1")
    monkeypatch.setenv("OVERLAP_AI_DIAGNOSTICS_FILE", str(tmp_path / "trace.jsonl"))
    monkeypatch.setattr(kakao, "KAKAO_REST_API_KEY", "test-only-key")
    responses = iter([
        httpx.Response(200, request=httpx.Request("GET", "https://example.test"), json={"documents": []}),
        httpx.Response(401, request=httpx.Request("GET", "https://example.test"), text="private error body"),
    ])
    monkeypatch.setattr(kakao.httpx, "get", lambda *args, **kwargs: next(responses))

    token = diagnostics.begin()
    assert kakao.search_places("synthetic query") == []
    diagnostics.finish(token, status_code=200, elapsed_ms=1)

    token = diagnostics.begin()
    with pytest.raises(httpx.HTTPStatusError):
        kakao.search_places("synthetic query")
    diagnostics.finish(token, status_code=200, elapsed_ms=1)

    rows = [json.loads(line) for line in (tmp_path / "trace.jsonl").read_text(encoding="utf-8").splitlines()]
    assert rows[0]["counts"]["kakao_http_status_200"] == 1
    assert rows[0]["counts"]["kakao_successful_responses"] == 1
    assert rows[0]["counts"]["kakao_response_documents"] == 0
    assert rows[1]["counts"]["kakao_http_status_401"] == 1
    assert "private error body" not in (tmp_path / "trace.jsonl").read_text(encoding="utf-8")
