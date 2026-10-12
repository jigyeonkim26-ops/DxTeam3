class AiPlaceRecommendation {
  const AiPlaceRecommendation({required this.name, required this.address, required this.latitude, required this.longitude, required this.reason, required this.sourceUrl, required this.matchedKeywords});
  final String name;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String reason;
  final String sourceUrl;
  final List<String> matchedKeywords;
  factory AiPlaceRecommendation.fromJson(Map<String, dynamic> json) => AiPlaceRecommendation(
    name: json['name'] as String,
    address: json['address'] as String?,
    latitude: (json['latitude'] as num?)?.toDouble(), longitude: (json['longitude'] as num?)?.toDouble(),
    reason: json['reason'] as String, sourceUrl: json['source_url'] as String,
    matchedKeywords: (json['matched_keywords'] as List<dynamic>? ?? const []).whereType<String>().toList(),
  );
}
