import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:overlap_app/features/map/services/current_location_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('overlap/current_location');
  const service = GeolocatorCurrentLocationService();
  late GeolocatorPlatform original;
  late _Permissions permissions;
  late int gpsRequests;

  setUp(() {
    original = GeolocatorPlatform.instance;
    permissions = _Permissions();
    GeolocatorPlatform.instance = permissions;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    gpsRequests = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getCurrentPosition');
          gpsRequests++;
          return {'latitude': 35.1107137, 'longitude': 126.8778041};
        });
  });

  tearDown(() {
    GeolocatorPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('Android requests permission then reads native GPS without geolocator position requests', () async {
    permissions.permission = LocationPermission.denied;
    final location = await service.getCurrentLocation();
    expect(permissions.requests, 1);
    expect(gpsRequests, 1);
    expect(location.latitude, 35.1107137);
    expect(location.longitude, 126.8778041);
  });

  test('denied permission prevents GPS requests', () async {
    permissions.permission = LocationPermission.denied;
    permissions.response = LocationPermission.denied;
    await expectLater(
      service.getCurrentLocation(),
      throwsA(_reason(CurrentLocationFailureReason.permissionDenied)),
    );
    expect(permissions.requests, 1);
    expect(gpsRequests, 0);
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
      expect(gpsRequests, 0);
    },
  );

  test('disabled services prevent GPS requests', () async {
    permissions.enabled = false;
    await expectLater(
      service.getCurrentLocation(),
      throwsA(_reason(CurrentLocationFailureReason.serviceDisabled)),
    );
    expect(gpsRequests, 0);
  });

  for (final reason in [
    CurrentLocationFailureReason.timeout,
    CurrentLocationFailureReason.permissionDenied,
    CurrentLocationFailureReason.serviceDisabled,
    CurrentLocationFailureReason.unavailable,
  ]) {
    test('native ${reason.name} preserves failure guidance', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => throw PlatformException(code: reason.name),
          );
      await expectLater(service.getCurrentLocation(), throwsA(_reason(reason)));
    });
  }
}

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

  @override
  Future<bool> isLocationServiceEnabled() async => enabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    return response;
  }
}
