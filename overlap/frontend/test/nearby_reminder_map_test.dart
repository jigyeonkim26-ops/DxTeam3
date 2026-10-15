import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overlap_app/features/map/models/current_location.dart';
import 'package:overlap_app/features/map/models/nearby_reminder.dart';
import 'package:overlap_app/features/map/screens/map_screen.dart';
import 'package:overlap_app/features/map/services/current_location_service.dart';
import 'package:overlap_app/features/map/services/nearby_reminder_api.dart';
import 'package:overlap_app/features/map/widgets/nearby_reminder_banner.dart';
import 'package:overlap_app/features/memory/screens/record_detail_screen.dart';
import 'package:overlap_app/shared/models/emotion.dart';
import 'package:overlap_app/shared/models/place.dart';
import 'package:overlap_app/shared/models/record.dart';
import 'package:overlap_app/shared/models/user.dart';

void main() {
  testWidgets('shows a nearby-record banner and opens its record', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final location = const CurrentLocation(
      latitude: 35.1107137,
      longitude: 126.8778041,
    );
    final reminder = NearbyReminder(
      record: Record(
        id: '42',
        author: const User(id: '1', name: '나'),
        place: const Place(
          id: '7',
          name: 'CGI센터',
          address: '광주',
          latitude: 35.1107137,
          longitude: 126.8778041,
        ),
        createdAt: DateTime(2026, 10, 15),
        content: '기록 내용',
        emotion: Emotion.good,
      ),
      distanceMeters: 0,
      notificationId: 9,
      notificationCreated: true,
    );
    var readNotificationId = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapScreen(
            locationService: _Location(location),
            nearbyReminderService: _Reminders([reminder]),
            markNotificationRead: (id) async => readNotificationId = id,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('현재 위치'));
    await tester.pumpAndSettle();

    expect(find.byType(NearbyReminderBanner), findsOneWidget);
    expect(find.text('근처에 기록한 장소가 있어요'), findsOneWidget);
    expect(find.text('CGI센터 · 0m'), findsOneWidget);

    await tester.tap(find.text('근처에 기록한 장소가 있어요'));
    await tester.pumpAndSettle();

    expect(readNotificationId, 9);
    expect(find.byType(RecordDetailScreen), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}

class _Location implements CurrentLocationService {
  const _Location(this.location);
  final CurrentLocation location;

  @override
  Future<CurrentLocation> getCurrentLocation() async => location;
}

class _Reminders implements NearbyReminderService {
  const _Reminders(this.items);
  final List<NearbyReminder> items;

  @override
  Future<List<NearbyReminder>> check(CurrentLocation location) async => items;
}
