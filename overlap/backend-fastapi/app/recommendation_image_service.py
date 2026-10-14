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

    # The image-search response has no title/contents field, so its result
    # cannot be tied back to a specific place safely. Blog search provides
    # title, contents, locality context, and a representative thumbnail.
    SEARCH_URL = "https://dapi.kakao.com/v2/search/blog"
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
    def _safe_image_url(value: object) -> str | None:
        if not isinstance(value, str):
            return None
        parsed = urlparse(value.strip())
        if not parsed.hostname:
            return None
        if parsed.scheme == "https":
            return value.strip()
        # Daum Blog currently returns some thumbnails over HTTP on Kakao's
        # CDN. Android's network_security_config already permits this host.
        if parsed.scheme == "http" and (
            parsed.hostname == "kakaocdn.net"
            or parsed.hostname.endswith(".kakaocdn.net")
        ):
            return value.strip()
        return None

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
                "AI recommendation image lookup outcome=%s source=daum_blog status=200 candidates=%d accepted=%d rejected_missing_metadata=%d rejected_name=%d rejected_region=%d rejected_url=%d",
                "external" if result else "placeholder",
                len(documents) if isinstance(documents, list) else 0,
                1 if result else 0,
                rejected.get("missing_metadata", 0),
                rejected.get("name", 0),
                rejected.get("region", 0),
                rejected.get("url", 0),
            )
            if not documents:
                logger.info("AI recommendation image lookup outcome=placeholder reason=no_search_results")
        except httpx.HTTPStatusError as exc:
            logger.info(
                "AI recommendation image lookup outcome=placeholder source=daum_blog status=%d reason=http_error",
                exc.response.status_code,
            )
            result = None
        except Exception as exc:
            logger.info(
                "AI recommendation image lookup outcome=placeholder source=daum_blog reason=%s",
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
        rejected = {"missing_metadata": 0, "name": 0, "region": 0, "url": 0}
        if not isinstance(documents, list):
            return None, rejected
        expected_name = cls._normalize(place.name)
        if len(expected_name) < 2:
            return None, rejected
        for document in documents[:cls.MAX_RESULTS]:
            if not isinstance(document, dict):
                continue
            title = str(document.get("title") or "")
            contents = str(document.get("contents") or "")
            evidence = cls._normalize(f"{title} {contents}")
            if not evidence:
                rejected["missing_metadata"] += 1
                continue

            # Blog search exposes content metadata unlike image search. A
            # qualified request alone is not proof: the exact Kakao place name
            # must also occur in the returned title or summary.
            if expected_name not in evidence:
                rejected["name"] += 1
                continue

            # The Daum API does not return Kakao Place IDs or coordinates for
            # image/blog results. Require a matching locality as a second
            # independent signal; if the place name itself contains the
            # locality (for example, a city-named facility), that is usable.
            region_terms = [cls._normalize(term) for term in cls._region_terms(place.address)]
            place_name_evidence = cls._normalize(place.name)
            has_region_signal = any(term and term in evidence for term in region_terms)
            name_contains_region = any(
                term and term in place_name_evidence for term in region_terms
            )
            if region_terms and not (has_region_signal or name_contains_region):
                rejected["region"] += 1
                continue

            image_url = cls._safe_image_url(document.get("thumbnail"))
            if not image_url:
                rejected["url"] += 1
                continue
            site = str(document.get("blogname") or "Kakao Daum Blog").strip()
            return {
                "image_url": image_url,
                "image_source": "kakao_daum_blog_search",
                "image_origin_type": "external",
                "image_credit": site or "Kakao Daum Blog",
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
        finally:
            # External Daum Blog lookups below can take several seconds.
            # Release the read-only DB connection before starting them.
            try:
                db.rollback()
            except Exception as exc:
                logger.warning("AI recommendation image DB transaction release failed exception=%s", type(exc).__name__)

        logger.info(
            "AI recommendation record image matches candidates=%d kakao_id_missing=%d accessible_photo_matches=%d no_accessible_photo_match=%d",
            len(recommendations),
            sum(1 for item in recommendations if not item.kakao_place_id),
            len(record_photos),
            max(0, len(ids) - len(record_photos)),
        )

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
