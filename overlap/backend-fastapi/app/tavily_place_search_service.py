"""Collect source-backed place candidates using Tavily search results."""

import re
from typing import Any, Callable

import httpx
from pydantic import ValidationError

from .config import TAVILY_API_KEY
from .models import PlaceCandidate, PlaceCandidateResponse, PreferenceKeyword, RecommendationMemory
from .place_web_search_service import PlaceSearchNotConfiguredError, PlaceSearchParseError, PlaceWebSearchService


class TavilySearchRequestError(Exception):
    pass


class TavilyPlaceSearchService:
    API_URL = "https://api.tavily.com/search"

    def __init__(self, api_key: str | None = None,
                 post_json: Callable[..., Any] | None = None) -> None:
        self.api_key = TAVILY_API_KEY if api_key is None else api_key.strip()
        self._post_json = post_json or httpx.post

    @staticmethod
    def _normalize(value: str | None) -> str:
        return " ".join((value or "").split()).casefold()

    @classmethod
    def build_queries(cls, location: str, keywords: list[PreferenceKeyword]) -> list[str]:
        ordered = sorted(keywords[:5], key=lambda item: item.score, reverse=True)
        terms = [item.keyword for item in ordered]
        if not terms:
            return []
        queries = [f"{location} {' '.join(terms[:3])} 명소"]
        if len(terms) >= 1:
            queries.append(f"{location} {terms[0]} 전망 장소")
        if len(terms) >= 3:
            queries.append(f"{location} {terms[1]} {terms[2]} 장소")
        return list(dict.fromkeys(queries))[:3]

    @staticmethod
    def _place_name(title: str, content: str) -> str | None:
        # Search titles commonly contain a place followed by a page/site description.
        # Use only a concise leading proper-name-like segment, never the full title blindly.
        cleaned_title = title.strip()
        parts = re.split(r"\s*(?:[-|:·]|\||–|—)\s*", cleaned_title, maxsplit=1)
        first = parts[0].strip()
        if not first or len(first) > 80 or first.casefold() in {"home", "검색", "명소"}:
            return None
        # A whole page title is not automatically a place name. Without a title
        # separator, accept it only when the page content explicitly starts with it.
        if len(parts) == 1 and not content.lstrip().startswith(first):
            return None
        if first not in content and len(first.split()) > 6:
            return None
        return first

    def search_candidates(self, keywords: list[PreferenceKeyword],
                          memories: list[RecommendationMemory]) -> PlaceCandidateResponse:
        if not keywords:
            return PlaceCandidateResponse(candidates=[])
        if not self.api_key:
            raise PlaceSearchNotConfiguredError
        location = PlaceWebSearchService.infer_region(memories) or "대한민국"
        queries = self.build_queries(location, keywords)
        used_places = {self._normalize(memory.place_name) for memory in memories}
        candidates: list[PlaceCandidate] = []
        seen: set[tuple[str, str]] = set()
        try:
            for query in queries:
                response = self._post_json(
                    self.API_URL,
                    headers={"Authorization": f"Bearer {self.api_key}"},
                    json={"query": query, "search_depth": "basic", "max_results": 10}, timeout=30.0,
                )
                response.raise_for_status()
                results = response.json().get("results", [])
                if not isinstance(results, list):
                    raise TypeError("results must be an array")
                for result in results:
                    if not isinstance(result, dict):
                        continue
                    title, url, content = result.get("title"), result.get("url"), result.get("content")
                    if not all(isinstance(value, str) and value.strip() for value in (title, url, content)):
                        continue
                    name = self._place_name(title, content)
                    if name is None or self._normalize(name) in used_places:
                        continue
                    identity = (self._normalize(name), "")
                    if identity in seen:
                        continue
                    seen.add(identity)
                    matched = [item.keyword for item in keywords if item.keyword.casefold() in (title + " " + content).casefold()]
                    candidates.append(PlaceCandidate(
                        name=name, address=None, latitude=None, longitude=None,
                        matched_keywords=matched, summary=content[:500], source_url=url,
                    ))
                    if len(candidates) == 10:
                        return PlaceCandidateResponse(candidates=candidates)
        except httpx.HTTPError as exc:
            raise TavilySearchRequestError from exc
        except (TypeError, ValueError, ValidationError) as exc:
            raise PlaceSearchParseError from exc
        return PlaceCandidateResponse(candidates=candidates)
