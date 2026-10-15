"""Opt-in, privacy-safe JSONL diagnostics for recommendation requests."""
from __future__ import annotations

import contextvars
import hashlib
import hmac
import json
import os
import re
import secrets
import threading
import time
import uuid
from collections import Counter
from pathlib import Path

from .config import BASE_DIR

_current: contextvars.ContextVar[dict | None] = contextvars.ContextVar("recommendation_diagnostic", default=None)
_db_path: contextvars.ContextVar[str | None] = contextvars.ContextVar("database_request_path", default=None)
_lock = threading.Lock()
_process_salt = os.getenv("OVERLAP_DIAGNOSTIC_SALT", "").encode() or secrets.token_bytes(32)
_SAFE_VALUE_FIELDS = {"category", "region_explicit", "cache_hit", "record_count", "session_status",
                      "preference_provider_http_status", "tavily_skip_reason"}
_SAFE_DECISION_REASONS = {
    "region_mismatch", "previously_visited", "category_mismatch", "duplicate_kakao_id",
    "duplicate_name", "passed_search_filters", "category_not_confirmed",
    "no_matching_positive_record_category", "no_candidate_specific_preference_evidence",
    "explicit_negative_type_conflict",
    "grade_A", "grade_B", "confirmed", "insufficient", "place_identity_unverified",
    "unavailable", "skipped",
}


def enabled() -> bool:
    return (os.getenv("OVERLAP_ENV", "").strip().lower() == "development"
            and os.getenv("OVERLAP_AI_DIAGNOSTICS", "").strip().lower() in {"1", "true", "yes"})


def begin() -> contextvars.Token:
    state = {"trace_id": str(uuid.uuid4()), "started": time.perf_counter(), "stages_ms": {},
             "counts": Counter(), "errors": Counter(), "flags": {}, "user": None}
    return _current.set(state)


def trace_id() -> str | None:
    state = _current.get()
    return state["trace_id"] if state else None


def set_db_path(path: str):
    return _db_path.set(path)


def reset_db_path(token) -> None:
    _db_path.reset(token)


def current_db_path() -> str | None:
    return _db_path.get()


def normalized_request_path(path: str) -> str:
    # Diagnostics receive only a path template-like form, never query strings or IDs.
    return re.sub(r"(?<=/)\d+(?=/|$)", "{id}", path)


def set_user(user_id: int) -> None:
    state = _current.get()
    if not state:
        return
    state["user"] = hmac.new(_process_salt, str(user_id).encode(), hashlib.sha256).hexdigest()[:16]


def add_count(name: str, value: int = 1) -> None:
    state = _current.get()
    if state:
        state["counts"][name] += int(value)


def set_count(name: str, value: int) -> None:
    """Set a request-wide unique metric that may be observed in multiple stages."""
    state = _current.get()
    if state and re.fullmatch(r"[a-zA-Z0-9_.-]{1,80}", name):
        state["counts"][name] = max(0, int(value))


def max_count(name: str, value: int) -> None:
    """Keep the maximum safe scalar observed across repeated search stages."""
    state = _current.get()
    if state and re.fullmatch(r"[a-zA-Z0-9_.-]{1,80}", name):
        state["counts"][name] = max(state["counts"].get(name, 0), max(0, int(value)))


def count_unique(name: str, value: str | None) -> None:
    """Track distinct opaque IDs without writing provider IDs to the diagnostic file."""
    state = _current.get()
    if not state or value is None or not re.fullmatch(r"[a-zA-Z0-9_.-]{1,80}", name):
        return
    digest = hashlib.sha256(str(value).encode("utf-8")).hexdigest()
    state.setdefault("unique", {}).setdefault(name, set()).add(digest)


def _candidate_key(candidate_id: str | None) -> str:
    return hashlib.sha256(str(candidate_id or "missing").encode("utf-8")).hexdigest()[:16]


def category_result(candidate_id: str | None, *, category_present: bool, group_code_class: str,
                    category_name_mapped: bool, category_name_mapping: list[str],
                    mapped_categories: list[str], status: str,
                    reason: str) -> None:
    state = _current.get()
    if not state:
        return
    allowed_categories = {"food", "bar", "cafe", "nature", "activity"}
    allowed_classes = {"food", "cafe", "tourism", "culture", "non_target", "unknown"}
    allowed_statuses = {"confirmed", "verification_required", "mismatch", "unknown"}
    allowed_name_mappings = {
        "food", "bar_subcategory", "cafe", "nature_subcategory", "activity_subcategory",
    }
    allowed_reasons = {
        "confirmed", "category_requires_specific_subtype", "known_category_mismatch",
        "no_recognized_category_evidence", "insufficient_category_evidence",
    }
    state.setdefault("category_diagnostics", []).append({
        "candidate_key": _candidate_key(candidate_id),
        "category_present": bool(category_present),
        "group_code_class": group_code_class if group_code_class in allowed_classes else "unknown",
        "category_name_mapped": bool(category_name_mapped),
        "category_name_mapping": sorted(set(category_name_mapping) & allowed_name_mappings),
        "mapped_categories": sorted(set(mapped_categories) & allowed_categories),
        "status": status if status in allowed_statuses else "unknown",
        "reason": reason if reason in allowed_reasons else "insufficient_category_evidence",
    })


def personalization_result(candidate_id: str | None, *, categories: list[str],
                            positive_category_present: bool | None, linkable_facet_count: int | None,
                            matched_facet_count: int | None, type_evidence_accepted: bool | None,
                            result: str, reason: str,
                            category_affinity_record_count: int | None = None,
                            category_affinity_distinct_target_count: int | None = None) -> None:
    state = _current.get()
    if not state:
        return
    allowed_categories = {"food", "bar", "cafe", "nature", "activity"}
    allowed_results = {"rejected", "grade_A", "grade_B"}
    allowed_reasons = {
        "category_not_confirmed", "no_positive_facet_for_confirmed_category",
        "positive_facet_without_verified_feature", "nature_type_evidence_accepted",
        "specific_category_type_evidence_accepted", "verified_same_record_feature", "other",
        "explicit_negative_type_conflict",
        "repeated_positive_category_affinity",
        "category_affinity_below_threshold",
    }
    state.setdefault("personalization_diagnostics", []).append({
        "candidate_key": _candidate_key(candidate_id),
        "candidate_categories": sorted(set(categories) & allowed_categories),
        "positive_category_present": (bool(positive_category_present)
                                      if positive_category_present is not None else None),
        "linkable_positive_facet_count": (max(0, int(linkable_facet_count))
                                          if linkable_facet_count is not None else None),
        "matched_positive_facet_count": (max(0, int(matched_facet_count))
                                         if matched_facet_count is not None else None),
        "type_evidence_accepted": (bool(type_evidence_accepted)
                                   if type_evidence_accepted is not None else None),
        "category_affinity_record_count": (
            max(0, int(category_affinity_record_count))
            if category_affinity_record_count is not None else 0
        ),
        "category_affinity_distinct_target_count": (
            max(0, int(category_affinity_distinct_target_count))
            if category_affinity_distinct_target_count is not None else 0
        ),
        "result": result if result in allowed_results else "rejected",
        "reason": reason if reason in allowed_reasons else "other",
    })


def tavily_result(candidate_id: str | None, *, request_status: str, result_count: int,
                  identity_match_count: int, confirmed_term_count: int, invalid_url_count: int,
                  place_name_match: bool, region_match: bool, locality_match: bool,
                  cache_used: bool, rejection_reason: str) -> None:
    state = _current.get()
    if not state:
        return
    allowed_statuses = {"cache_hit", "response_ok", "error", "missing_configuration"}
    allowed_reasons = {
        "feature_confirmed", "place_identity_not_verified", "preference_feature_not_found",
        "unsafe_or_missing_evidence_url", "provider_unavailable",
    }
    state.setdefault("tavily_diagnostics", []).append({
        "candidate_key": _candidate_key(candidate_id),
        "request_status": request_status if request_status in allowed_statuses else "error",
        "result_count": max(0, int(result_count)),
        "identity_match_count": max(0, int(identity_match_count)),
        "confirmed_term_count": max(0, int(confirmed_term_count)),
        "invalid_url_count": max(0, int(invalid_url_count)),
        "place_name_match": bool(place_name_match),
        "region_match": bool(region_match),
        "locality_match": bool(locality_match),
        "cache_used": bool(cache_used),
        "rejection_reason": rejection_reason if rejection_reason in allowed_reasons else "provider_unavailable",
    })


def set_value(name: str, value) -> None:
    state = _current.get()
    if state and name in _SAFE_VALUE_FIELDS:
        # Only scalar, non-content diagnostic values are accepted.
        if isinstance(value, (str, int, float, bool)) or value is None:
            state[name] = value


def set_flag(name: str, value: bool = True) -> None:
    state = _current.get()
    if state:
        state["flags"][name] = bool(value)


def stage(name: str, elapsed_ms: int) -> None:
    state = _current.get()
    if state:
        state["stages_ms"][name] = state["stages_ms"].get(name, 0) + max(0, int(elapsed_ms))


def error(stage_name: str, reason: str) -> None:
    state = _current.get()
    if state and re.fullmatch(r"[a-zA-Z0-9_.-]{1,60}", stage_name) and re.fullmatch(r"[a-zA-Z0-9_.-]{1,80}", reason):
        state["errors"][f"{stage_name}:{reason}"] += 1


def decision(stage_name: str, candidate_id: str | None, decision_value: str, reason: str) -> None:
    state = _current.get()
    if not state:
        return
    if reason not in _SAFE_DECISION_REASONS:
        reason = "other"
    if decision_value not in {"accepted", "rejected", "merged", "not_confirmed"}:
        decision_value = "unknown"
    candidate_key = _candidate_key(candidate_id)
    state.setdefault("decisions", []).append({
        "stage": stage_name, "candidate_key": candidate_key,
        "decision": decision_value, "reason": reason,
    })


def finish(token: contextvars.Token, *, status_code: int, elapsed_ms: int) -> None:
    state = _current.get()
    try:
        if not state or not enabled():
            return
        output = {
            "event": "recommendation_trace", "trace_id": state["trace_id"],
            "user_anon": state["user"],
            "code_version": os.getenv("OVERLAP_CODE_VERSION", os.getenv("GIT_COMMIT", "unversioned")),
            "http_status": status_code, "total_elapsed_ms": elapsed_ms,
            "stages_ms": state["stages_ms"],
            "counts": {**dict(state["counts"]),
                       **{name: len(values) for name, values in state.get("unique", {}).items()}},
            "errors": dict(state["errors"]), "flags": state["flags"],
            "candidate_decisions": state.get("decisions", []),
            "category_diagnostics": state.get("category_diagnostics", []),
            "personalization_diagnostics": state.get("personalization_diagnostics", []),
            "tavily_diagnostics": state.get("tavily_diagnostics", []),
            "category": state.get("category"), "cache_hit": state.get("cache_hit"),
            "record_count": state.get("record_count"),
            "preference_provider_http_status": state.get("preference_provider_http_status"),
            "tavily_skip_reason": state.get("tavily_skip_reason"),
            "final_count": state["counts"].get("final_recommendations", 0),
        }
        configured = os.getenv("OVERLAP_AI_DIAGNOSTICS_FILE", "").strip()
        path = Path(configured) if configured else BASE_DIR / "logs" / "ai_recommendation_diagnostics.jsonl"
        path.parent.mkdir(parents=True, exist_ok=True)
        with _lock, path.open("a", encoding="utf-8") as output_file:
            output_file.write(json.dumps(output, ensure_ascii=False, separators=(",", ":")) + "\n")
    finally:
        _current.reset(token)


def write_db_event(event: dict) -> None:
    """Write allowlisted SQLAlchemy pool timing metrics to a separate dev JSONL."""
    if not enabled():
        return
    safe = {key: value for key, value in event.items()
            if key in {"event", "trace_id", "path", "lease_ms", "wait_ms", "scope_ms", "pool_size", "checked_out",
                       "overflow", "timeout_limit_ms", "outcome"}
            and isinstance(value, (str, int, float, bool, type(None)))}
    path = BASE_DIR / "logs" / "database_pool_diagnostics.jsonl"
    path.parent.mkdir(parents=True, exist_ok=True)
    with _lock, path.open("a", encoding="utf-8") as output_file:
        output_file.write(json.dumps(safe, separators=(",", ":")) + "\n")
