import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../models/current_location.dart';

enum CurrentLocationFailureReason {
  serviceDisabled,
  permissionDenied,
  permissionPermanentlyDenied,
  timeout,
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

  static const _androidLocation = MethodChannel('overlap/current_location');

  Future<CurrentLocation> _readCoordinates() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      // Both geolocator_android 5.1.1+1 providers register NMEA listeners,
      // even with useMSLAltitude=false. Read GPS without those listeners.
      try {
        final coordinates = await _androidLocation.invokeMapMethod<String, num>(
          'getCurrentPosition',
        );
        return CurrentLocation(
          latitude: coordinates!['latitude']!.toDouble(),
          longitude: coordinates['longitude']!.toDouble(),
        );
      } on PlatformException catch (error) {
        throw CurrentLocationFailure(switch (error.code) {
          'serviceDisabled' => CurrentLocationFailureReason.serviceDisabled,
          'permissionDenied' => CurrentLocationFailureReason.permissionDenied,
          'timeout' => CurrentLocationFailureReason.timeout,
          _ => CurrentLocationFailureReason.unavailable,
        });
      }
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 15),
      ),
    );
    return CurrentLocation(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }

  @override
  Future<CurrentLocation> getCurrentLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const CurrentLocationFailure(
          CurrentLocationFailureReason.serviceDisabled,
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
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

      final location = await _readCoordinates();
      if (!location.hasValidCoordinates) {
        throw const CurrentLocationFailure(
          CurrentLocationFailureReason.unavailable,
        );
      }
      return location;
    } on CurrentLocationFailure {
      rethrow;
    } on TimeoutException {
      throw const CurrentLocationFailure(CurrentLocationFailureReason.timeout);
    } on LocationServiceDisabledException {
      throw const CurrentLocationFailure(
        CurrentLocationFailureReason.serviceDisabled,
      );
    } on PermissionDeniedException {
      throw const CurrentLocationFailure(
        CurrentLocationFailureReason.permissionDenied,
      );
    } catch (_) {
      throw const CurrentLocationFailure(
        CurrentLocationFailureReason.unavailable,
      );
    }
  }
}
