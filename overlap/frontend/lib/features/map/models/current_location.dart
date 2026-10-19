/// A device location used only to focus the map for the current session.
class CurrentLocation {
  const CurrentLocation({
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    this.timestamp,
  });

  final double latitude;
  final double longitude;
  final double? accuracyMeters;
  final DateTime? timestamp;

  static const maximumAcceptedAccuracyMeters = 200.0;
  static const maximumLocationAge = Duration(minutes: 2);

  /// Broad mainland/Jeju/Dokdo coverage guard for recentering the Korean map.
  /// It prevents emulator coordinates in distant regions from replacing the
  /// user's current map with an unsupported Kakao tile area.
  bool get isWithinKakaoKoreaBounds =>
      hasValidCoordinates &&
      latitude >= 33.0 &&
      latitude <= 38.8 &&
      longitude >= 124.5 &&
      longitude <= 132.1;

  bool get hasValidCoordinates =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  bool get hasAcceptableAccuracy =>
      accuracyMeters != null &&
      accuracyMeters!.isFinite &&
      accuracyMeters! > 0 &&
      accuracyMeters! <= maximumAcceptedAccuracyMeters;

  bool get isRecent => timestamp != null && _isTimestampRecent(timestamp!);

  bool _isTimestampRecent(DateTime value) {
    final age = DateTime.now().toUtc().difference(value.toUtc());
    return age >= const Duration(seconds: -30) && age <= maximumLocationAge;
  }

  @override
  bool operator ==(Object other) =>
      other is CurrentLocation &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.accuracyMeters == accuracyMeters &&
      other.timestamp == timestamp;

  @override
  int get hashCode =>
      Object.hash(latitude, longitude, accuracyMeters, timestamp);
}
