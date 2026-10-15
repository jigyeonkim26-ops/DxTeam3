import json

from app import recommendation_diagnostics as diagnostics
from app import db
from sqlalchemy import create_engine
from sqlalchemy.exc import TimeoutError as SQLAlchemyTimeoutError
import pytest


def test_trace_jsonl_has_one_trace_and_no_user_identifiers(tmp_path, monkeypatch):
    output = tmp_path / "recommendation.jsonl"
    monkeypatch.setenv("OVERLAP_ENV", "development")
    monkeypatch.setenv("OVERLAP_AI_DIAGNOSTICS", "true")
    monkeypatch.setenv("OVERLAP_AI_DIAGNOSTICS_FILE", str(output))
    monkeypatch.setenv("OVERLAP_DIAGNOSTIC_SALT", "test-only-salt")
    token = diagnostics.begin()
    trace = diagnostics.trace_id()
    diagnostics.set_user(1234)
    diagnostics.set_value("category", "all")
    diagnostics.set_value("record_count", 14)
    diagnostics.add_count("generated_queries", 12)
    diagnostics.add_count("executed_queries", 6)
    diagnostics.decision("region_filter", "98765", "rejected", "region_mismatch")
    diagnostics.finish(token, status_code=200, elapsed_ms=987)

    row = json.loads(output.read_text(encoding="utf-8"))
    assert row["trace_id"] == trace
    assert row["http_status"] == 200
    assert row["counts"]["generated_queries"] == 12
    assert row["counts"]["executed_queries"] == 6
    assert row["candidate_decisions"][0]["reason"] == "region_mismatch"
    assert "user_anon" in row and row["user_anon"] != "1234"
    assert "email" not in output.read_text(encoding="utf-8")


def test_request_unique_metrics_and_safe_provider_status_are_not_double_counted(tmp_path, monkeypatch):
    output = tmp_path / "recommendation.jsonl"
    monkeypatch.setenv("OVERLAP_ENV", "development")
    monkeypatch.setenv("OVERLAP_AI_DIAGNOSTICS", "1")
    monkeypatch.setenv("OVERLAP_AI_DIAGNOSTICS_FILE", str(output))
    token = diagnostics.begin()
    diagnostics.set_count("searchable_positive_facets", 64)
    diagnostics.set_count("searchable_positive_facets", 64)  # continuation sees the same analysis
    diagnostics.count_unique("kakao_unique_raw_places", "place-1")
    diagnostics.count_unique("kakao_unique_raw_places", "place-1")
    diagnostics.count_unique("kakao_unique_raw_places", "place-2")
    diagnostics.set_value("preference_provider_http_status", 402)
    diagnostics.finish(token, status_code=200, elapsed_ms=1)

    row = json.loads(output.read_text(encoding="utf-8"))
    assert row["counts"]["searchable_positive_facets"] == 64
    assert row["counts"]["kakao_unique_raw_places"] == 2
    assert row["preference_provider_http_status"] == 402
    assert "place-1" not in output.read_text(encoding="utf-8")


def test_diagnostic_anonymization_is_stable_per_user_and_distinct_between_users(tmp_path, monkeypatch):
    output = tmp_path / "users.jsonl"
    monkeypatch.setenv("OVERLAP_ENV", "development")
    monkeypatch.setenv("OVERLAP_AI_DIAGNOSTICS", "1")
    monkeypatch.setenv("OVERLAP_AI_DIAGNOSTICS_FILE", str(output))
    monkeypatch.setenv("OVERLAP_DIAGNOSTIC_SALT", "stable-test-salt")

    for user_id in (101, 101, 202):
        token = diagnostics.begin()
        diagnostics.set_user(user_id)
        diagnostics.finish(token, status_code=200, elapsed_ms=1)

    users = [json.loads(line)["user_anon"] for line in output.read_text(encoding="utf-8").splitlines()]
    assert users[0] == users[1]
    assert users[0] != users[2]
    assert all(value not in {"101", "202"} for value in users)


def test_diagnostics_are_disabled_outside_development(tmp_path, monkeypatch):
    output = tmp_path / "must-not-exist.jsonl"
    monkeypatch.setenv("OVERLAP_ENV", "production")
    monkeypatch.setenv("OVERLAP_AI_DIAGNOSTICS", "true")
    monkeypatch.setenv("OVERLAP_AI_DIAGNOSTICS_FILE", str(output))
    token = diagnostics.begin()
    diagnostics.finish(token, status_code=200, elapsed_ms=10)
    assert not output.exists()


def test_database_pool_jsonl_uses_separate_file_and_allowlisted_fields(tmp_path, monkeypatch):
    monkeypatch.setenv("OVERLAP_ENV", "development")
    monkeypatch.setenv("OVERLAP_AI_DIAGNOSTICS", "true")
    monkeypatch.setattr(diagnostics, "BASE_DIR", tmp_path)
    diagnostics.write_db_event({
        "event": "connection_lease", "path": "/records/{record_id}/photos/{photo_id}",
        "lease_ms": 2500, "pool_size": 5, "checked_out": 2, "overflow": 0,
        "secret": "must-not-appear",
    })
    path = tmp_path / "logs" / "database_pool_diagnostics.jsonl"
    row = json.loads(path.read_text(encoding="utf-8"))
    assert row["lease_ms"] == 2500
    assert "secret" not in row


def test_pool_wait_and_connection_lease_are_separate_metrics(tmp_path, monkeypatch):
    monkeypatch.setenv("OVERLAP_ENV", "development")
    monkeypatch.setenv("OVERLAP_AI_DIAGNOSTICS", "true")
    monkeypatch.setattr(diagnostics, "BASE_DIR", tmp_path)
    engine = create_engine(
        "sqlite://", poolclass=db.DiagnosticQueuePool,
        pool_size=1, max_overflow=0, pool_timeout=0.02,
    )
    held = engine.connect()
    with pytest.raises(SQLAlchemyTimeoutError):
        engine.connect()
    held.close()
    rows = [json.loads(line) for line in
            (tmp_path / "logs" / "database_pool_diagnostics.jsonl").read_text(encoding="utf-8").splitlines()]
    wait = next(row for row in rows if row["event"] == "pool_wait" and row["outcome"] == "timed_out")
    assert wait["outcome"] == "timed_out"
    assert wait["wait_ms"] >= 10
    engine.dispose()
