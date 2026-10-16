import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overlap_app/features/map/models/current_location.dart';
import 'package:overlap_app/features/map/models/nearby_reminder.dart';
import 'package:overlap_app/features/map/screens/map_screen.dart';
import 'package:overlap_app/features/map/services/kakao_map_local_server.dart';
import 'package:overlap_app/features/map/services/current_location_service.dart';
import 'package:overlap_app/features/map/services/nearby_reminder_api.dart';
import 'package:overlap_app/features/map/widgets/map_view.dart';

void main() {
  mainMapPinTest();

  test('identifies coordinates outside the Korean Kakao map area', () {
    expect(
      const CurrentLocation(
        latitude: 35.1,
        longitude: 126.8,
      ).isWithinKakaoKoreaBounds,
      isTrue,
    );
    expect(
      const CurrentLocation(
        latitude: 40.7,
        longitude: -74.0,
      ).isWithinKakaoKoreaBounds,
      isFalse,
    );
    expect(
      const CurrentLocation(
        latitude: 126.8,
        longitude: 35.1,
      ).isWithinKakaoKoreaBounds,
      isFalse,
    );
    expect(
      const CurrentLocation(
        latitude: double.nan,
        longitude: 126.8,
      ).isWithinKakaoKoreaBounds,
      isFalse,
    );
  });

  testWidgets('equal GPS readings issue a new recenter request on every tap', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final service = _FakeCurrentLocationService()
      ..results = [
        const CurrentLocation(latitude: 35.1, longitude: 126.8),
        const CurrentLocation(latitude: 35.1, longitude: 126.8),
      ];
    await tester.pumpWidget(_screen(service));
    await tester.tap(find.byTooltip('현재 위치'));
    await tester.pumpAndSettle();
    final first = tester.widget<MapView>(find.byType(MapView));
    await tester.tap(find.byTooltip('현재 위치'));
    await tester.pumpAndSettle();
    final second = tester.widget<MapView>(find.byType(MapView));
    expect(second.currentLocation, first.currentLocation);
    expect(second.currentLocationRequestId, first.currentLocationRequestId + 1);
    expect(service.calls, 2);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('passes the retrieved GPS coordinates to the map', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    const location = CurrentLocation(
      latitude: 35.1107137,
      longitude: 126.8778041,
    );
    final service = _FakeCurrentLocationService()..result = location;
    await tester.pumpWidget(_screen(service));

    await tester.tap(find.byTooltip('현재 위치'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<MapView>(find.byType(MapView)).currentLocation,
      location,
    );
    expect(service.calls, 1);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('out of region GPS leaves map in place and skips reminders', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const local = CurrentLocation(latitude: 35.1, longitude: 126.8);
    const outside = CurrentLocation(latitude: 40.7, longitude: -74.0);
    final locationService = _FakeCurrentLocationService()
      ..results = [local, outside];
    final reminders = _CountingReminders();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapScreen(
            locationService: locationService,
            nearbyReminderService: reminders,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('현재 위치'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('현재 위치'));
    await tester.pumpAndSettle();

    expect(tester.widget<MapView>(find.byType(MapView)).currentLocation, local);
    expect(
      find.text('에뮬레이터 위치가 Kakao 국내 지도 표시 범위 밖입니다. 에뮬레이터 위치를 확인해주세요.'),
      findsOneWidget,
    );
    expect(reminders.calls, 1);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('shows guidance when location permission is denied', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final service = _FakeCurrentLocationService()
      ..failure = const CurrentLocationFailure(
        CurrentLocationFailureReason.permissionDenied,
      );
    await tester.pumpWidget(_screen(service));

    await tester.tap(find.byTooltip('현재 위치'));
    await tester.pumpAndSettle();

    expect(find.text('현재 위치를 사용하려면 위치 권한이 필요합니다.'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('asks the user to enable location services', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final service = _FakeCurrentLocationService()
      ..failure = const CurrentLocationFailure(
        CurrentLocationFailureReason.serviceDisabled,
      );
    await tester.pumpWidget(_screen(service));

    await tester.tap(find.byTooltip('현재 위치'));
    await tester.pumpAndSettle();

    expect(find.text('위치 서비스를 켜주세요.'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('shows settings guidance when permission is permanently denied', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final service = _FakeCurrentLocationService()
      ..failure = const CurrentLocationFailure(
        CurrentLocationFailureReason.permissionPermanentlyDenied,
      );
    await tester.pumpWidget(_screen(service));

    await tester.tap(find.byTooltip('현재 위치'));
    await tester.pumpAndSettle();

    expect(find.text('위치 권한이 영구적으로 거부되었습니다. 설정에서 허용해주세요.'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('shows retry guidance when the location request times out', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final service = _FakeCurrentLocationService()
      ..failure = const CurrentLocationFailure(
        CurrentLocationFailureReason.timeout,
      );
    await tester.pumpWidget(_screen(service));

    await tester.tap(find.byTooltip('현재 위치'));
    await tester.pumpAndSettle();

    expect(find.text('현재 위치를 확인하지 못했습니다. 다시 시도해주세요.'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('refreshes the map with the latest GPS reading on each tap', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    const first = CurrentLocation(latitude: 35.1, longitude: 126.8);
    const second = CurrentLocation(latitude: 35.2, longitude: 126.9);
    final service = _FakeCurrentLocationService()..results = [first, second];
    await tester.pumpWidget(_screen(service));

    await tester.tap(find.byTooltip('현재 위치'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('현재 위치'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<MapView>(find.byType(MapView)).currentLocation,
      second,
    );
    expect(service.calls, 2);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('ignores repeated taps while a location request is pending', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final response = Completer<CurrentLocation>();
    final service = _FakeCurrentLocationService()..response = response;
    await tester.pumpWidget(_screen(service));

    await tester.tap(find.byTooltip('현재 위치'));
    await tester.pump();
    await tester.tap(find.byTooltip('현재 위치'));
    await tester.pump();

    expect(service.calls, 1);
    response.complete(const CurrentLocation(latitude: 35.1, longitude: 126.8));
    await tester.pumpAndSettle();
    expect(service.calls, 1);
    debugDefaultTargetPlatformOverride = null;
  });
}

void mainMapPinTest() {
  test('keeps one current-location overlay separate from other map pins', () {
    final page = KakaoMapLocalServer().debugMapPage('test-key');

    expect(page, contains('var overlays = [];'));
    expect(page, contains('var searchOverlay = null;'));
    expect(page, contains('var currentLocationOverlay = null;'));
    expect(page, contains('var pendingCurrentLocation = null;'));
    expect(page, contains('currentLocationOverlay.setMap(null);'));
    expect(
      page,
      contains('currentLocationOverlay = new kakao.maps.CustomOverlay'),
    );
  });
}

Widget _screen(_FakeCurrentLocationService service) => MaterialApp(
  home: Scaffold(body: MapScreen(locationService: service)),
);

class _FakeCurrentLocationService implements CurrentLocationService {
  CurrentLocation? result;
  CurrentLocationFailure? failure;
  Completer<CurrentLocation>? response;
  List<CurrentLocation> results = [];
  var calls = 0;

  @override
  Future<CurrentLocation> getCurrentLocation() {
    calls++;
    final currentFailure = failure;
    if (currentFailure != null) throw currentFailure;
    final pendingResponse = response;
    if (pendingResponse != null) return pendingResponse.future;
    if (results.isNotEmpty) return Future.value(results.removeAt(0));
    return Future.value(result!);
  }
}

class _CountingReminders implements NearbyReminderService {
  var calls = 0;

  @override
  Future<List<NearbyReminder>> check(CurrentLocation location) async {
    calls++;
    return const [];
  }
}
