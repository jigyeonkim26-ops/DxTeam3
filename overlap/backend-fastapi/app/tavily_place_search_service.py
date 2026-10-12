"""Tavily candidate search for record-derived place preferences."""

import re
from typing import Any, Callable

import httpx

from .ai_recommendation_errors import AIConfigurationError, AIRequestError, AIResponseError
from .ai_recommendation_models import PlaceCandidate, PlaceCandidateResponse, PreferenceKeyword
from .config import TAVILY_API_KEY
from .recommendation_record_adapter import RecommendationRecord


class TavilyPlaceSearchService:
    API_URL = "https://api.tavily.com/search"

    def __init__(self, api_key: str | None = None, post_json: Callable[..., Any] | None = None) -> None:
        self.api_key = TAVILY_API_KEY if api_key is None else api_key.strip()
        self._post_json = post_json or httpx.post

    @staticmethod
    def _normalize(value: str | None) -> str:
        return " ".join((value or "").split()).casefold()

    @classmethod
    def build_queries(cls, location: str, keywords: list[PreferenceKeyword]) -> list[str]:
        terms = [item.keyword for item in sorted(keywords, key=lambda item: item.score, reverse=True)[:5]]
        if not terms:
            return []
        queries = [f"{location} {' '.join(terms[:3])} 명소", f"{location} {terms[0]} 전망 장소"]
        if len(terms) >= 3:
            queries.append(f"{location} {terms[1]} {terms[2]} 장소")
        return list(dict.fromkeys(queries))[:3]

    @staticmethod
    def _place_name(title: str, content: str) -> str | None:
        parts = re.split(r"\s*(?:[-|:·]|\||–|—)\s*", title.strip(), maxsplit=1)
        name = parts[0].strip()
        if not name or len(name) > 80 or name.casefold() in {"home", "검색", "명소"}:
            return None
        if len(parts) == 1 and not content.lstrip().startswith(name):
            return None
        return name

    def search_candidates(self, keywords: list[PreferenceKeyword], records: list[RecommendationRecord]) -> PlaceCandidateResponse:
        if not keywords:
            return PlaceCandidateResponse()
        if not self.api_key:
            raise AIConfigurationError("Tavily is not configured")
        location = next((record.address.split()[0] for record in records if record.address), "대한민국")
        used_names = {self._normalize(record.place_name) for record in records}
        candidates, seen = [], set()
        try:
            for query in self.build_queries(location, keywords):
                response = self._post_json(self.API_URL, headers={"Authorization": f"Bearer {self.api_key}"},
                                           json={"query": query, "search_depth": "basic", "max_results": 10}, timeout=30.0)
                response.raise_for_status()
                for result in response.json().get("results", []):
                    title, url, content = result.get("title"), result.get("url"), result.get("content")
                    if not all(isinstance(value, str) and value.strip() for value in (title, url, content)):
                        continue
                    name = self._place_name(title, content)
                    normalized = self._normalize(name)
                    if not name or normalized in used_names or normalized in seen:
                        continue
                    seen.add(normalized)
                    candidates.append(PlaceCandidate(
                        name=name, address=None, latitude=None, longitude=None,
                        matched_keywords=[item.keyword for item in keywords if item.keyword.casefold() in (title + content).casefold()],
                        summary=content[:500], source_url=url,
                    ))
                    if len(candidates) == 10:
                        return PlaceCandidateResponse(candidates=candidates)
        except httpx.HTTPError as exc:
            raise AIRequestError from exc
        except (AttributeError, TypeError, ValueError) as exc:
            raise AIResponseError from exc
        return PlaceCandidateResponse(candidates=candidates)
