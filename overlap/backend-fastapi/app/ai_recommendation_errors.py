class AIRecommendationError(Exception):
    pass


class AIConfigurationError(AIRecommendationError):
    pass


class AIRequestError(AIRecommendationError):
    pass


class AIResponseError(AIRecommendationError):
    pass


class InvalidRecommendationError(AIResponseError):
    pass
