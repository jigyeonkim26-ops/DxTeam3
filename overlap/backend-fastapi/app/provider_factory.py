"""Select independently configurable LLM and search providers."""

from .gemini_place_recommendation_service import GeminiPlaceRecommendationService
from .gemini_preference_keyword_service import GeminiPreferenceKeywordService
from .openrouter_place_recommendation_service import OpenRouterPlaceRecommendationService
from .openrouter_preference_keyword_service import OpenRouterPreferenceKeywordService
from .place_recommendation_service import PlaceRecommendationService
from .place_web_search_service import PlaceWebSearchService
from .preference_keyword_service import PreferenceKeywordService
from .tavily_place_search_service import TavilyPlaceSearchService


def build_preference_service(provider: str):
    if provider == "gemini":
        return GeminiPreferenceKeywordService()
    if provider == "openrouter":
        return OpenRouterPreferenceKeywordService()
    return PreferenceKeywordService()


def build_search_service(provider: str):
    return TavilyPlaceSearchService() if provider == "tavily" else PlaceWebSearchService()


def build_recommendation_service(provider: str):
    if provider == "gemini":
        return GeminiPlaceRecommendationService()
    if provider == "openrouter":
        return OpenRouterPlaceRecommendationService()
    return PlaceRecommendationService()
