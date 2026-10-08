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
