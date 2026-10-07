class AiPlaceRecommendation {
  const AiPlaceRecommendation({
    required this.rank,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.matchScore,
    required this.matchedKeywords,
    required this.reason,
    required this.sourceUrl,
  });

  final int rank;
  final String name;
  final String? address;
  final double? latitude;
  final double? longitude;
  final double matchScore;
  final List<String> matchedKeywords;
  final String reason;
  final String sourceUrl;

  factory AiPlaceRecommendation.fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final reason = json['reason'];
    final sourceUrl = json['source_url'];
    final rank = json['rank'];
    final matchScore = json['match_score'];
    final keywords = json['matched_keywords'];
    final address = json['address'];

    if (name is! String ||
        reason is! String ||
        sourceUrl is! String ||
        rank is! int ||
        matchScore is! num ||
        (address != null && address is! String) ||
        keywords is! List ||
        keywords.any((keyword) => keyword is! String)) {
      throw const FormatException('Invalid AI recommendation item.');
    }

    return AiPlaceRecommendation(
      rank: rank,
      name: name,
      address: address as String?,
      latitude: _parseOptionalDouble(json['latitude']),
      longitude: _parseOptionalDouble(json['longitude']),
      matchScore: matchScore.toDouble(),
      matchedKeywords: keywords.cast<String>(),
      reason: reason,
      sourceUrl: sourceUrl,
    );
  }

  static double? _parseOptionalDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    throw const FormatException('Invalid AI recommendation coordinates.');
  }
}

class AiPlaceRecommendationResponse {
  const AiPlaceRecommendationResponse({required this.recommendations});

  final List<AiPlaceRecommendation> recommendations;

  factory AiPlaceRecommendationResponse.fromJson(Map<String, dynamic> json) {
    final items = json['recommendations'];
    if (items is! List) {
      throw const FormatException('Invalid AI recommendations response.');
    }
    return AiPlaceRecommendationResponse(
      recommendations: items.map((item) {
        if (item is! Map<String, dynamic>) {
          throw const FormatException('Invalid AI recommendation item.');
        }
        return AiPlaceRecommendation.fromJson(item);
      }).toList(growable: false),
    );
  }
}
