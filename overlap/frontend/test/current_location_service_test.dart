import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:overlap_app/features/map/services/current_location_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const service = GeolocatorCurrentLocationService();
  late GeolocatorPlatform original;
  late _Permissions permissions;

  setUp(() {
    original = GeolocatorPlatform.instance;
    permissions = _Permissions();
    GeolocatorPlatform.instance = permissions;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    GeolocatorPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'Android uses Geolocator fused-preferred settings for a fresh fix',
    () async {
      permissions.permission = LocationPermission.denied;
      final location = await service.getCurrentLocation();
      expect(permissions.requests, 1);
      expect(permissions.positionRequests, 1);
      expect(location.latitude, 35.1107137);
      expect(location.longitude, 126.8778041);
      expect(location.accuracyMeters, 18);
      expect(location.hasAcceptableAccuracy, isTrue);
      final settings = permissions.requestedSettings.single! as AndroidSettings;
      expect(settings.accuracy, LocationAccuracy.high);
      expect(settings.timeLimit, const Duration(seconds: 25));
      expect(settings.forceLocationManager, isFalse);
    },
  );

  test('denied permission prevents GPS requests', () async {
    permissions.permission = LocationPermission.denied;
    permissions.response = LocationPermission.denied;
    await expectLater(
      service.getCurrentLocation(),
      throwsA(_reason(CurrentLocationFailureReason.permissionDenied)),
    );
    expect(permissions.requests, 1);
    expect(permissions.positionRequests, 0);
  });

  test(
    'permanent denial prevents permission dialogs and GPS requests',
    () async {
      permissions.permission = LocationPermission.deniedForever;
      await expectLater(
        service.getCurrentLocation(),
        throwsA(
          _reason(CurrentLocationFailureReason.permissionPermanentlyDenied),
        ),
      );
      expect(permissions.requests, 0);
      expect(permissions.positionRequests, 0);
    },
  );

  test('disabled services prevent GPS requests', () async {
    permissions.enabled = false;
    await expectLater(
      service.getCurrentLocation(),
      throwsA(_reason(CurrentLocationFailureReason.serviceDisabled)),
    );
    expect(permissions.positionRequests, 0);
  });

  test(
    'retries a timed out high-accuracy request once with balanced accuracy',
    () async {
      permissions.positionResponses.addAll([
        TimeoutException('high accuracy timeout'),
        _position(accuracy: 90),
      ]);

      final location = await service.getCurrentLocation();

      expect(location.accuracyMeters, 90);
      expect(permissions.positionRequests, 2);
      final first = permissions.requestedSettings[0]! as AndroidSettings;
      final retry = permissions.requestedSettings[1]! as AndroidSettings;
      expect(first.accuracy, LocationAccuracy.high);
      expect(retry.accuracy, LocationAccuracy.medium);
      expect(retry.forceLocationManager, isFalse);
      expect(retry.timeLimit, const Duration(seconds: 12));
    },
  );

  test('rejects coordinates whose reported accuracy is too poor', () async {
    permissions.position = _position(accuracy: 250);
    await expectLater(
      service.getCurrentLocation(),
      throwsA(_reason(CurrentLocationFailureReason.inaccurate)),
    );
    expect(permissions.positionRequests, 1);
  });

  test('rejects a stale fix rather than presenting it as current', () async {
    permissions.position = _position(
      timestamp: DateTime.now().subtract(const Duration(minutes: 3)),
    );
    await expectLater(
      service.getCurrentLocation(),
      throwsA(_reason(CurrentLocationFailureReason.stale)),
    );
  });

  test('does not accept a timeout retry with poor balanced accuracy', () async {
    permissions.positionResponses.addAll([
      TimeoutException('high accuracy timeout'),
      _position(accuracy: 500),
    ]);
    await expectLater(
      service.getCurrentLocation(),
      throwsA(_reason(CurrentLocationFailureReason.inaccurate)),
    );
    expect(permissions.positionRequests, 2);
  });

  test(
    'preserves timeout when both Android location requests time out',
    () async {
      permissions.positionResponses.addAll([
        TimeoutException('first timeout'),
        TimeoutException('retry timeout'),
      ]);
      await expectLater(
        service.getCurrentLocation(),
        throwsA(_reason(CurrentLocationFailureReason.timeout)),
      );
      expect(permissions.positionRequests, 2);
    },
  );
}

Position _position({double accuracy = 18, DateTime? timestamp}) => Position(
  longitude: 126.8778041,
  latitude: 35.1107137,
  timestamp: timestamp ?? DateTime.now().toUtc(),
  accuracy: accuracy,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

Matcher _reason(CurrentLocationFailureReason reason) =>
    isA<CurrentLocationFailure>().having(
      (failure) => failure.reason,
      'reason',
      reason,
    );

class _Permissions extends GeolocatorPlatform {
  bool enabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission response = LocationPermission.whileInUse;
  int requests = 0;
  int positionRequests = 0;
  Position position = _position();
  final List<Object> positionResponses = [];
  final List<LocationSettings?> requestedSettings = [];

  @override
  Future<bool> isLocationServiceEnabled() async => enabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    return response;
  }

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    positionRequests++;
    requestedSettings.add(locationSettings);
    if (positionResponses.isNotEmpty) {
      final next = positionResponses.removeAt(0);
      if (next is Exception) throw next;
      return next as Position;
    }
    return position;
  }
}
