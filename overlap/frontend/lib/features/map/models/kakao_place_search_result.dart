class KakaoPlaceSearchResult {
  const KakaoPlaceSearchResult({
    required this.kakaoPlaceId,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.placeUrl,
  });

  final String kakaoPlaceId;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String placeUrl;

  factory KakaoPlaceSearchResult.fromJson(Map<String, dynamic> json) {
    String requiredString(String key) {
      final value = json[key];
      if (value is String && value.trim().isNotEmpty) return value;
      throw FormatException('필수 장소 검색 필드가 올바르지 않습니다: $key');
    }

    double requiredCoordinate(String key) {
      final value = json[key];
      final coordinate = value is num
          ? value.toDouble()
          : value is String
          ? double.tryParse(value)
          : null;
      if (coordinate == null || !coordinate.isFinite) {
        throw FormatException('장소 좌표 필드가 올바르지 않습니다: $key');
      }
      return coordinate;
    }

    return KakaoPlaceSearchResult(
      kakaoPlaceId: requiredString('kakao_place_id'),
      name: requiredString('name'),
      address: requiredString('address'),
      latitude: requiredCoordinate('latitude'),
      longitude: requiredCoordinate('longitude'),
      placeUrl: requiredString('place_url'),
    );
  }
}
