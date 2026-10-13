class AiPlaceRecommendation {
  const AiPlaceRecommendation({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.reason,
    required this.sourceUrl,
    required this.matchedKeywords,
    this.kakaoPlaceId,
    this.imageUrl,
    this.imageSource,
    this.imageOriginType = 'placeholder',
    this.imageCredit,
  });

  final String? kakaoPlaceId;
  final String name;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String reason;
  final String sourceUrl;
  final List<String> matchedKeywords;
  final String? imageUrl;
  final String? imageSource;
  final String imageOriginType;
  final String? imageCredit;

  factory AiPlaceRecommendation.fromJson(Map<String, dynamic> json) =>
      AiPlaceRecommendation(
        kakaoPlaceId: json['kakao_place_id'] as String?,
        name: json['name'] as String,
        address: json['address'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        reason: json['reason'] as String,
        sourceUrl: json['source_url'] as String,
        matchedKeywords:
            (json['matched_keywords'] as List<dynamic>? ?? const [])
                .whereType<String>()
                .toList(),
        imageUrl: json['image_url'] as String?,
        imageSource: json['image_source'] as String?,
        imageOriginType: json['image_origin_type'] as String? ?? 'placeholder',
        imageCredit: json['image_credit'] as String?,
      );
}
