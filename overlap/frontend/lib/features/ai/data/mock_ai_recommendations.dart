import '../../../shared/models/place.dart';

class AiPlaceRecommendation {
  const AiPlaceRecommendation({
    required this.place,
    required this.keywords,
    required this.reason,
    required this.imageSeed,
  });

  final Place place;
  final List<String> keywords;
  final String reason;
  final int imageSeed;
}

/// AI recommendations are populated by an analysis response.
const List<List<AiPlaceRecommendation>> mockAiRecommendationSets = [];
