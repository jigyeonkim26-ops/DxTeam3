import 'dart:convert';

import '../../../shared/models/place.dart';

/// Ephemeral map focus for a selected search result; it is never persisted.
class MapSearchPlace {
  const MapSearchPlace({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    this.address,
  });

  factory MapSearchPlace.fromPlace(Place place) => MapSearchPlace(
    id: place.id,
    name: place.name,
    latitude: place.latitude,
    longitude: place.longitude,
    address: place.address,
  );

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final String? address;

  bool get hasValidCoordinates =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'latitude': latitude,
    'longitude': longitude,
  };

  String toJsonString() => jsonEncode(toJson());

  @override
  bool operator ==(Object other) =>
      other is MapSearchPlace &&
      other.id == id &&
      other.name == name &&
      other.address == address &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(id, name, address, latitude, longitude);
}
