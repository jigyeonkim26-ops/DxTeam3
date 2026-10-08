class SavedPlace {
  const SavedPlace({
    required this.placeId,
    required this.name,
    required this.address,
    required this.roadAddress,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
  });

  final int placeId;
  final String name;
  final String? address;
  final String? roadAddress;
  final double latitude;
  final double longitude;
  final DateTime createdAt;

  String? get displayAddress => roadAddress ?? address;

  factory SavedPlace.fromJson(Map<String, dynamic> json) {
    final placeId = json['place_id'];
    final name = json['name'];
    final latitude = json['latitude'];
    final longitude = json['longitude'];
    final createdAt = json['created_at'];
    if (placeId is! int ||
        placeId <= 0 ||
        name is! String ||
        name.trim().isEmpty ||
        latitude is! num ||
        longitude is! num ||
        createdAt is! String) {
      throw const FormatException('Invalid saved place response.');
    }

    return SavedPlace(
      placeId: placeId,
      name: name.trim(),
      address: json['address'] is String ? json['address'] as String : null,
      roadAddress:
          json['road_address'] is String ? json['road_address'] as String : null,
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      createdAt: DateTime.parse(createdAt).toLocal(),
    );
  }
}

class SavedPlaceState {
  const SavedPlaceState({
    required this.placeId,
    required this.saved,
    required this.savedCount,
  });

  final int placeId;
  final bool saved;
  final int savedCount;

  factory SavedPlaceState.fromJson(Map<String, dynamic> json) {
    final placeId = json['place_id'];
    final saved = json['saved'];
    final savedCount = json['saved_count'];
    if (placeId is! int ||
        placeId <= 0 ||
        saved is! bool ||
        savedCount is! int ||
        savedCount < 0) {
      throw const FormatException('Invalid saved place state response.');
    }
    return SavedPlaceState(
      placeId: placeId,
      saved: saved,
      savedCount: savedCount,
    );
  }
}
