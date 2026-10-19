import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../models/current_location.dart';

enum CurrentLocationFailureReason {
  serviceDisabled,
  permissionDenied,
  permissionPermanentlyDenied,
  timeout,
  inaccurate,
  stale,
  unavailable,
}

class CurrentLocationFailure implements Exception {
  const CurrentLocationFailure(this.reason);

  final CurrentLocationFailureReason reason;
}

abstract interface class CurrentLocationService {
  Future<CurrentLocation> getCurrentLocation();
}

class GeolocatorCurrentLocationService implements CurrentLocationService {
  const GeolocatorCurrentLocationService();

  Future<CurrentLocation> _readCoordinates() async {
    final stopwatch = Stopwatch()..start();
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    late final Position position;
    if (isAndroid) {
      debugPrint(
        '[GPS] geolocator request started provider=automatic accuracy=high '
        'timeout_ms=25000 force_location_manager=false',
      );
      try {
        position = await Geolocator.getCurrentPosition(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 25),
            forceLocationManager: false,
          ),
        );
      } on TimeoutException {
        debugPrint(
          '[GPS] geolocator high-accuracy request timed out; '
          'retrying once with balanced accuracy timeout_ms=12000',
        );
        position = await Geolocator.getCurrentPosition(
          locationSettings: AndroidSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 12),
            forceLocationManager: false,
          ),
        );
      }
    } else {
      debugPrint(
        '[GPS] geolocator request started accuracy=high timeout_ms=25000',
      );
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 25),
        ),
      );
    }
    final location = CurrentLocation(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      timestamp: position.timestamp,
    );
    if (kDebugMode) {
      debugPrint(
        '[GPS_DIAGNOSTIC] lat=${location.latitude.toStringAsFixed(3)} '
        'lon=${location.longitude.toStringAsFixed(3)} coordinate_order=lat_lon '
        'kakao_korea_bounds=${location.isWithinKakaoKoreaBounds}',
      );
    }
    debugPrint(
      '[GPS] geolocator request completed elapsed_ms=${stopwatch.elapsedMilliseconds} '
      'coordinates_valid=${location.hasValidCoordinates} '
      'accuracy_m=${location.accuracyMeters?.toStringAsFixed(1)} '
      'accuracy_acceptable=${location.hasAcceptableAccuracy} '
      'reading_recent=${location.isRecent}',
    );
    return location;
  }

  @override
  Future<CurrentLocation> getCurrentLocation() async {
    final stopwatch = Stopwatch()..start();
    var stage = 'service_status';
    debugPrint('[GPS] request started platform=${defaultTargetPlatform.name}');
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      debugPrint('[GPS] location_service_enabled=$serviceEnabled');
      if (!serviceEnabled) {
        throw const CurrentLocationFailure(
          CurrentLocationFailureReason.serviceDisabled,
        );
      }

      stage = 'permission_check';
      var permission = await Geolocator.checkPermission();
      debugPrint('[GPS] permission=${permission.name}');
      if (permission == LocationPermission.denied) {
        stage = 'permission_request';
        permission = await Geolocator.requestPermission();
        debugPrint('[GPS] permission_after_request=${permission.name}');
      }
      if (permission == LocationPermission.denied) {
        throw const CurrentLocationFailure(
          CurrentLocationFailureReason.permissionDenied,
        );
      }
      if (permission == LocationPermission.deniedForever) {
        throw const CurrentLocationFailure(
          CurrentLocationFailureReason.permissionPermanentlyDenied,
        );
      }

      stage = 'coordinate_request';
      final location = await _readCoordinates();
      if (!location.hasValidCoordinates) {
        throw const CurrentLocationFailure(
          CurrentLocationFailureReason.unavailable,
        );
      }
      if (!location.hasAcceptableAccuracy) {
        throw const CurrentLocationFailure(
          CurrentLocationFailureReason.inaccurate,
        );
      }
      if (!location.isRecent) {
        throw const CurrentLocationFailure(CurrentLocationFailureReason.stale);
      }
      debugPrint(
        '[GPS] request succeeded elapsed_ms=${stopwatch.elapsedMilliseconds} '
        'coordinates_valid=true',
      );
      return location;
    } on CurrentLocationFailure catch (failure) {
      debugPrint(
        '[GPS] request failed stage=$stage reason=${failure.reason.name} '
        'elapsed_ms=${stopwatch.elapsedMilliseconds}',
      );
      rethrow;
    } on TimeoutException catch (error) {
      debugPrint(
        '[GPS] request failed stage=$stage type=${error.runtimeType} '
        'elapsed_ms=${stopwatch.elapsedMilliseconds}',
      );
      throw const CurrentLocationFailure(CurrentLocationFailureReason.timeout);
    } on LocationServiceDisabledException catch (error) {
      debugPrint(
        '[GPS] request failed stage=$stage type=${error.runtimeType} '
        'elapsed_ms=${stopwatch.elapsedMilliseconds}',
      );
      throw const CurrentLocationFailure(
        CurrentLocationFailureReason.serviceDisabled,
      );
    } on PermissionDeniedException catch (error) {
      debugPrint(
        '[GPS] request failed stage=$stage type=${error.runtimeType} '
        'elapsed_ms=${stopwatch.elapsedMilliseconds}',
      );
      throw const CurrentLocationFailure(
        CurrentLocationFailureReason.permissionDenied,
      );
    } catch (error) {
      debugPrint(
        '[GPS] request failed stage=$stage type=${error.runtimeType} '
        'elapsed_ms=${stopwatch.elapsedMilliseconds}',
      );
      throw const CurrentLocationFailure(
        CurrentLocationFailureReason.unavailable,
      );
    }
  }
}
