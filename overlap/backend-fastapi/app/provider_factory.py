from .ai_recommendation_errors import AIConfigurationError
from .openrouter_place_recommendation_service import OpenRouterPlaceRecommendationService
from .openrouter_preference_keyword_service import OpenRouterPreferenceKeywordService
from .tavily_place_search_service import TavilyPlaceSearchService


def build_preference_service(provider: str):
    if provider == "openrouter":
        return OpenRouterPreferenceKeywordService()
    raise AIConfigurationError(f"Unsupported LLM_PROVIDER: {provider}")


def build_search_service(provider: str):
    if provider == "tavily":
        return TavilyPlaceSearchService()
    raise AIConfigurationError(f"Unsupported SEARCH_PROVIDER: {provider}")


def build_recommendation_service(provider: str):
    if provider == "openrouter":
        return OpenRouterPlaceRecommendationService()
    raise AIConfigurationError(f"Unsupported LLM_PROVIDER: {provider}")
