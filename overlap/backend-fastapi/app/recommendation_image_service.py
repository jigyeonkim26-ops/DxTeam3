"""Attach safe, optional thumbnails to already-ranked AI recommendations."""

from __future__ import annotations

import html
import logging
import re
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from typing import Callable
from urllib.parse import urlparse

import httpx
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from .ai_recommendation_models import PlaceRecommendationResponse, RecommendedPlace
from .config import KAKAO_REST_API_KEY
from .record_models import Place, Record, RecordPhoto
from .records import visibility

logger = logging.getLogger("uvicorn.error")


class RecommendationImageService:
    """Resolve accessible record photos first, then conservative Daum images.

    External results are cached in-process for an hour and misses for one minute.
    No recommendation ranking or place data is changed by this service.
    """

    SEARCH_URL = "https://dapi.kakao.com/v2/search/image"
    SEARCH_TIMEOUT_SECONDS = 2.5
    CACHE_TTL_SECONDS = 3600
    # A short negative cache avoids repeating failed lookups while allowing
    # corrected provider configuration/results to become visible quickly.
    MISS_TTL_SECONDS = 60
    MAX_CACHE_ENTRIES = 300
    MAX_RESULTS = 5
    _search_gate = threading.BoundedSemaphore(3)
    REGION_ALIASES = {
        "서울특별시": "서울", "부산광역시": "부산", "대구광역시": "대구",
        "인천광역시": "인천", "광주광역시": "광주", "대전광역시": "대전",
        "울산광역시": "울산", "세종특별자치시": "세종", "제주특별자치도": "제주",
        "전라남도": "전남", "전북특별자치도": "전북", "전라북도": "전북",
        "충청남도": "충남", "충청북도": "충북", "경상남도": "경남",
        "경상북도": "경북", "강원특별자치도": "강원", "강원도": "강원",
    }

    def __init__(self, search: Callable[[str], dict] | None = None) -> None:
        self._requires_key = search is None
        self._search = search or self._search_kakao
        self._cache: dict[str, tuple[float, dict | None]] = {}
        self._cache_lock = threading.Lock()

    def clear_cache(self) -> None:
        """Clear process-local image results for diagnostics and tests."""
        with self._cache_lock:
            self._cache.clear()

    @staticmethod
    def _https_url(value: object) -> str | None:
        if not isinstance(value, str):
            return None
        parsed = urlparse(value.strip())
        if parsed.scheme != "https" or not parsed.hostname:
            return None
        return value.strip()

    @staticmethod
    def _normalize(value: str) -> str:
        text = html.unescape(re.sub(r"<[^>]*>", " ", value)).casefold()
        return re.sub(r"[^\w]", "", text, flags=re.UNICODE)

    @classmethod
    def _region_terms(cls, address: str | None) -> list[str]:
        parts = (address or "").split()
        terms: list[str] = []
        if parts:
            first = parts[0]
            alias = cls.REGION_ALIASES.get(first)
            if alias:
                terms.append(alias)
            elif len(first) >= 2:
                terms.append(first[:2])
        if len(parts) > 1:
            terms.append(parts[1])
        return [term for term in terms if len(term) >= 2]

    @classmethod
    def _query(cls, place: RecommendedPlace) -> str | None:
        if not place.name.strip() or not place.address:
            return None
        locality = " ".join(place.address.split()[:2])
        if not locality:
            return None
        return f"{place.name.strip()} {locality}"

    def _search_kakao(self, query: str) -> dict:
        response = httpx.get(
            self.SEARCH_URL,
            headers={"Authorization": f"KakaoAK {KAKAO_REST_API_KEY}"},
            params={"query": query, "size": self.MAX_RESULTS, "sort": "accuracy"},
            timeout=self.SEARCH_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        return response.json()

    def _cached_external(self, place: RecommendedPlace) -> dict | None:
        key = place.kakao_place_id
        if not key:
            return None
        now = time.monotonic()
        with self._cache_lock:
            cached = self._cache.get(key)
            if cached and cached[0] > now:
                return cached[1]
            if cached:
                self._cache.pop(key, None)

        query = self._query(place)
        if not query:
            return None
        if self._requires_key and not KAKAO_REST_API_KEY:
            logger.info("AI recommendation image lookup outcome=placeholder reason=missing_api_key")
            return None
        if not self._search_gate.acquire(blocking=False):
            logger.info("AI recommendation image lookup outcome=placeholder reason=concurrency_limit")
            return None
        try:
            payload = self._search(query)
            documents = payload.get("documents", []) if isinstance(payload, dict) else []
            result, rejected = self._select_external_with_diagnostics(place, documents)
            logger.info(
                "AI recommendation image lookup outcome=%s source=daum status=200 candidates=%d accepted=%d rejected_name=%d rejected_url=%d",
                "external" if result else "placeholder",
                len(documents) if isinstance(documents, list) else 0,
                1 if result else 0,
                rejected.get("name", 0),
                rejected.get("url", 0),
            )
        except httpx.HTTPStatusError as exc:
            logger.info(
                "AI recommendation image lookup outcome=placeholder source=daum status=%d reason=http_error",
                exc.response.status_code,
            )
            result = None
        except Exception as exc:
            logger.info(
                "AI recommendation image lookup outcome=placeholder source=daum reason=%s",
                type(exc).__name__,
            )
            result = None
        finally:
            self._search_gate.release()

        ttl = self.CACHE_TTL_SECONDS if result else self.MISS_TTL_SECONDS
        with self._cache_lock:
            if len(self._cache) >= self.MAX_CACHE_ENTRIES:
                oldest = min(self._cache, key=lambda cache_key: self._cache[cache_key][0])
                self._cache.pop(oldest, None)
            self._cache[key] = (time.monotonic() + ttl, result)
        return result

    @classmethod
    def _select_external(cls, place: RecommendedPlace, documents: object) -> dict | None:
        result, _ = cls._select_external_with_diagnostics(place, documents)
        return result

    @classmethod
    def _select_external_with_diagnostics(
        cls, place: RecommendedPlace, documents: object
    ) -> tuple[dict | None, dict[str, int]]:
        rejected = {"name": 0, "url": 0}
        if not isinstance(documents, list):
            return None, rejected
        expected_name = cls._normalize(place.name)
        if len(expected_name) < 2:
            return None, rejected
        for document in documents[:cls.MAX_RESULTS]:
            if not isinstance(document, dict):
                continue
            title = str(document.get("title") or "")
            site = str(document.get("display_sitename") or "")
            title_text = cls._normalize(title)
            # Daum has already searched a place-and-locality-qualified query.
            # Search result metadata often omits the locality, so require a
            # strong place-name signal in the title instead of rejecting every
            # result whose blog/site metadata has no address.
            name_tokens = [cls._normalize(token) for token in place.name.split()]
            name_tokens = [token for token in name_tokens if len(token) >= 2]
            exact_name = expected_name in title_text
            token_match = bool(name_tokens) and all(token in title_text for token in name_tokens)
            branch_tokens = ("점", "지점", "센터", "본점", "병원", "공원")
            branch_match = any(
                token in title_text
                and (any(char.isdigit() for char in token) or token.endswith(branch_tokens))
                for token in name_tokens
            )
            distinctive_single_name = (
                len(name_tokens) == 1
                and name_tokens[0] in title_text
                and (len(name_tokens[0]) >= 4 or any(char.isdigit() for char in name_tokens[0]))
            )
            if not (exact_name or token_match or branch_match or distinctive_single_name):
                rejected["name"] += 1
                continue
            image_url = cls._https_url(document.get("thumbnail_url")) or cls._https_url(
                document.get("image_url")
            )
            if not image_url:
                rejected["url"] += 1
                continue
            return {
                "image_url": image_url,
                "image_source": "kakao_daum_image_search",
                "image_origin_type": "external",
                "image_credit": (str(site).strip() or None),
            }, rejected
        return None, rejected

    @staticmethod
    def _record_photo_urls(db: Session, user_id: int, place_ids: list[str]) -> dict[str, dict]:
        if not place_ids:
            return {}
        statement = (
            select(Place.external_place_id, Record.id, RecordPhoto.id)
            .join(Record, Record.place_id == Place.id)
            .join(RecordPhoto, RecordPhoto.record_id == Record.id)
            .where(
                func.lower(Place.provider) == "kakao",
                Place.external_place_id.in_(place_ids),
                visibility(user_id),
                func.lower(RecordPhoto.mime_type).like("image/%"),
            )
            .order_by(Record.created_at.desc(), RecordPhoto.sort_order, RecordPhoto.id)
        )
        photos: dict[str, dict] = {}
        for external_id, record_id, photo_id in db.execute(statement):
            if external_id and external_id not in photos:
                photos[external_id] = {
                    "image_url": f"/records/{record_id}/photos/{photo_id}",
                    "image_source": "overlap_record",
                    "image_origin_type": "record",
                    "image_credit": "OVERLAP 기록 사진",
                }
        return photos

    def enrich(
        self, db: Session, user_id: int, response: PlaceRecommendationResponse
    ) -> PlaceRecommendationResponse:
        recommendations = response.recommendations
        ids = list(dict.fromkeys(
            item.kakao_place_id for item in recommendations if item.kakao_place_id
        ))
        try:
            record_photos = self._record_photo_urls(db, user_id, ids)
        except Exception as exc:
            logger.info("AI recommendation record image lookup skipped exception=%s", type(exc).__name__)
            record_photos = {}

        unresolved = [item for item in recommendations if item.kakao_place_id not in record_photos]
        external_results: dict[str, dict | None] = {}
        if unresolved:
            with ThreadPoolExecutor(max_workers=min(3, len(unresolved))) as executor:
                futures = {
                    executor.submit(self._cached_external, item): item.kakao_place_id
                    for item in unresolved if item.kakao_place_id
                }
                for future in as_completed(futures):
                    place_id = futures[future]
                    try:
                        external_results[place_id] = future.result()
                    except Exception as exc:
                        logger.info("AI recommendation image lookup skipped exception=%s", type(exc).__name__)
                        external_results[place_id] = None

        enriched = []
        for item in recommendations:
            image = record_photos.get(item.kakao_place_id or "")
            if image is None:
                image = external_results.get(item.kakao_place_id or "")
            enriched.append(item.model_copy(update=image or {
                "image_url": None,
                "image_source": None,
                "image_origin_type": "placeholder",
                "image_credit": None,
            }))
        counts = {"record": 0, "external": 0, "placeholder": 0}
        for item in enriched:
            counts[item.image_origin_type] = counts.get(item.image_origin_type, 0) + 1
        logger.info(
            "AI recommendation image enrichment record=%d external=%d placeholder=%d",
            counts.get("record", 0), counts.get("external", 0), counts.get("placeholder", 0),
        )
        return response.model_copy(update={"recommendations": enriched})
