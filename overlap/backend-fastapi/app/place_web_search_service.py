"""Collect source-backed place candidates with the OpenAI Responses web search tool."""

import json
from collections import Counter
from typing import Any, Callable

import httpx
from pydantic import ValidationError

from .config import OPENAI_API_KEY
from .models import (
    PlaceCandidate,
    PlaceCandidateResponse,
    PreferenceKeyword,
    RecommendationMemory,
)


class PlaceSearchError(Exception):
    """Base error for the candidate place search step."""


class PlaceSearchNotConfiguredError(PlaceSearchError):
    pass


class OpenAIResponseRequestError(PlaceSearchError):
    pass


class WebSearchToolError(PlaceSearchError):
    pass


class PlaceSearchParseError(PlaceSearchError):
    pass


class PlaceWebSearchService:
    API_URL = "https://api.openai.com/v1/responses"
    DEFAULT_MODEL = "gpt-4o-mini"

    # Only recognize explicit Korean province/metro prefixes. If no address has
    # one, omit the region instead of guessing from a district or neighborhood.
    REGION_PREFIXES = {
        "\uc11c\uc6b8\ud2b9\ubcc4\uc2dc": "\uc11c\uc6b8\ud2b9\ubcc4\uc2dc",
        "\uc11c\uc6b8": "\uc11c\uc6b8\ud2b9\ubcc4\uc2dc",
        "\ubd80\uc0b0\uad11\uc5ed\uc2dc": "\ubd80\uc0b0\uad11\uc5ed\uc2dc",
        "\ubd80\uc0b0": "\ubd80\uc0b0\uad11\uc5ed\uc2dc",
        "\ub300\uad6c\uad11\uc5ed\uc2dc": "\ub300\uad6c\uad11\uc5ed\uc2dc",
        "\ub300\uad6c": "\ub300\uad6c\uad11\uc5ed\uc2dc",
        "\uc778\ucc9c\uad11\uc5ed\uc2dc": "\uc778\ucc9c\uad11\uc5ed\uc2dc",
        "\uc778\ucc9c": "\uc778\ucc9c\uad11\uc5ed\uc2dc",
        "\uad11\uc8fc\uad11\uc5ed\uc2dc": "\uad11\uc8fc\uad11\uc5ed\uc2dc",
        "\uad11\uc8fc": "\uad11\uc8fc\uad11\uc5ed\uc2dc",
        "\ub300\uc804\uad11\uc5ed\uc2dc": "\ub300\uc804\uad11\uc5ed\uc2dc",
        "\ub300\uc804": "\ub300\uc804\uad11\uc5ed\uc2dc",
        "\uc6b8\uc0b0\uad11\uc5ed\uc2dc": "\uc6b8\uc0b0\uad11\uc5ed\uc2dc",
        "\uc6b8\uc0b0": "\uc6b8\uc0b0\uad11\uc5ed\uc2dc",
        "\uc138\uc885\ud2b9\ubcc4\uc790\uce58\uc2dc": "\uc138\uc885\ud2b9\ubcc4\uc790\uce58\uc2dc",
        "\uc138\uc885": "\uc138\uc885\ud2b9\ubcc4\uc790\uce58\uc2dc",
        "\uacbd\uae30\ub3c4": "\uacbd\uae30\ub3c4",
        "\uacbd\uae30": "\uacbd\uae30\ub3c4",
        "\uac15\uc6d0\ud2b9\ubcc4\uc790\uce58\ub3c4": "\uac15\uc6d0\ud2b9\ubcc4\uc790\uce58\ub3c4",
        "\uac15\uc6d0\ub3c4": "\uac15\uc6d0\ub3c4",
        "\uac15\uc6d0": "\uac15\uc6d0\ub3c4",
        "\ucda9\uccad\ubd81\ub3c4": "\ucda9\uccad\ubd81\ub3c4",
        "\ucda9\ubd81": "\ucda9\uccad\ubd81\ub3c4",
        "\ucda9\uccad\ub0a8\ub3c4": "\ucda9\uccad\ub0a8\ub3c4",
        "\ucda9\ub0a8": "\ucda9\uccad\ub0a8\ub3c4",
        "\uc804\ub77c\ubd81\ub3c4": "\uc804\ub77c\ubd81\ub3c4",
        "\uc804\ubd81": "\uc804\ub77c\ubd81\ub3c4",
        "\uc804\ubd81\ud2b9\ubcc4\uc790\uce58\ub3c4": "\uc804\ubd81\ud2b9\ubcc4\uc790\uce58\ub3c4",
        "\uc804\ub77c\ub0a8\ub3c4": "\uc804\ub77c\ub0a8\ub3c4",
        "\uc804\ub0a8": "\uc804\ub77c\ub0a8\ub3c4",
        "\uacbd\uc0c1\ubd81\ub3c4": "\uacbd\uc0c1\ubd81\ub3c4",
        "\uacbd\ubd81": "\uacbd\uc0c1\ubd81\ub3c4",
        "\uacbd\uc0c1\ub0a8\ub3c4": "\uacbd\uc0c1\ub0a8\ub3c4",
        "\uacbd\ub0a8": "\uacbd\uc0c1\ub0a8\ub3c4",
        "\uc81c\uc8fc\ud2b9\ubcc4\uc790\uce58\ub3c4": "\uc81c\uc8fc\ud2b9\ubcc4\uc790\uce58\ub3c4",
        "\uc81c\uc8fc\ub3c4": "\uc81c\uc8fc\ud2b9\ubcc4\uc790\uce58\ub3c4",
        "\uc81c\uc8fc": "\uc81c\uc8fc\ud2b9\ubcc4\uc790\uce58\ub3c4",
    }

    def __init__(
        self,
        api_key: str | None = None,
        model: str = DEFAULT_MODEL,
        post_json: Callable[..., Any] | None = None,
    ) -> None:
        self.api_key = OPENAI_API_KEY if api_key is None else api_key.strip()
        self.model = model
        self._post_json = post_json or httpx.post

    @classmethod
    def infer_region(cls, memories: list[RecommendationMemory]) -> str | None:
        regions: list[str] = []
        for memory in memories:
            address = memory.address.strip()
            if not address:
                continue
            prefix = address.split(maxsplit=1)[0].rstrip(",")
            region = cls.REGION_PREFIXES.get(prefix)
            if region:
                regions.append(region)
        if not regions:
            return None
        counts = Counter(regions)
        # On a frequency tie, Counter preserves the first (most recent) address.
        return max(counts, key=counts.get)

    def search_candidates(
        self,
        keywords: list[PreferenceKeyword],
        memories: list[RecommendationMemory],
    ) -> PlaceCandidateResponse:
        if not keywords:
            return PlaceCandidateResponse(candidates=[])
        if not self.api_key:
            raise PlaceSearchNotConfiguredError

        terms = [item.keyword for item in keywords[:5]]
        region = self.infer_region(memories)
        location = region or "South Korea (region not specified)"
        query = (
            f"Find real, currently existing physical places in {location} that match "
            f"these preferences: {', '.join(terms)}. Search for named places people "
            "can visit. Exclude blog posts, news articles, general tourism pages, and "
            "broad regions without a specific place. Return only candidates supported "
            "by the web search sources. Do not invent names, addresses, URLs, or "
            "coordinates. Use a source URL only when it is one of the web search "
            "sources. Leave coordinates null; they are not being independently verified."
        )
        schema = {
            "type": "object",
            "properties": {
                "candidates": {
                    "type": "array",
                    "items": {
                        "type": "object",
                        "properties": {
                            "name": {"type": "string"},
                            "address": {"type": ["string", "null"]},
                            "matched_keywords": {"type": "array", "items": {"type": "string"}},
                            "summary": {"type": "string"},
                            "source_url": {"type": "string"},
                        },
                        "required": ["name", "address", "matched_keywords", "summary", "source_url"],
                        "additionalProperties": False,
                    },
                }
            },
            "required": ["candidates"],
            "additionalProperties": False,
        }
        payload = {
            "model": self.model,
            "tools": [{"type": "web_search"}],
            "tool_choice": "auto",
            "include": ["web_search_call.action.sources"],
            "input": query,
            "text": {
                "format": {
                    "type": "json_schema",
                    "name": "place_candidate_response",
                    "strict": True,
                    "schema": schema,
                }
            },
        }
        try:
            response = self._post_json(
                self.API_URL,
                headers={"Authorization": f"Bearer {self.api_key}"},
                json=payload,
                timeout=45.0,
            )
            response.raise_for_status()
        except httpx.HTTPError as exc:
            raise OpenAIResponseRequestError from exc

        try:
            envelope = response.json()
        except (ValueError, TypeError) as exc:
            raise PlaceSearchParseError from exc

        sources: set[str] = set()
        text_parts: list[str] = []
        web_search_called = False
        try:
            for output_item in envelope["output"]:
                if output_item.get("type") == "web_search_call":
                    web_search_called = True
                    if output_item.get("status") not in (None, "completed"):
                        raise WebSearchToolError
                    action = output_item.get("action") or {}
                    for source in action.get("sources", []):
                        if isinstance(source, dict) and isinstance(source.get("url"), str):
                            sources.add(source["url"])
                elif output_item.get("type") == "message":
                    for content in output_item.get("content", []):
                        if content.get("type") == "output_text":
                            text_parts.append(content.get("text", ""))
                            for annotation in content.get("annotations", []):
                                if annotation.get("type") == "url_citation":
                                    url = annotation.get("url")
                                    if isinstance(url, str):
                                        sources.add(url)
            if not web_search_called:
                raise WebSearchToolError
            result_text = "\n".join(text_parts).strip()
            if not result_text:
                raise PlaceSearchParseError
            parsed = json.loads(result_text)
            raw_candidates = parsed["candidates"]
            if not isinstance(raw_candidates, list):
                raise TypeError("candidates must be an array")
        except WebSearchToolError:
            raise
        except PlaceSearchParseError:
            raise
        except (json.JSONDecodeError, KeyError, IndexError, TypeError, ValueError, AttributeError) as exc:
            raise PlaceSearchParseError from exc

        verified: list[PlaceCandidate] = []
        seen: set[tuple[str, str]] = set()
        try:
            for raw in raw_candidates:
                candidate = PlaceCandidate.model_validate({
                    **raw,
                    # Coordinates are deliberately not accepted from model output.
                    "latitude": None,
                    "longitude": None,
                })
                if candidate.source_url not in sources:
                    continue
                normalized_name = " ".join(candidate.name.split()).casefold()
                normalized_address = " ".join((candidate.address or "").split()).casefold()
                identity = (normalized_name, normalized_address)
                if identity in seen:
                    continue
                seen.add(identity)
                verified.append(candidate)
                if len(verified) == 10:
                    break
        except (ValidationError, TypeError, ValueError) as exc:
            raise PlaceSearchParseError from exc

        return PlaceCandidateResponse(candidates=verified)
