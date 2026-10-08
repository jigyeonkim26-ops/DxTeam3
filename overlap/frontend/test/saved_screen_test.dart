import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overlap_app/features/user/screens/saved_screen.dart';
import 'package:overlap_app/features/user/services/saved_places_api.dart';

SavedPlacesApi responseApi(List<Map<String, dynamic>> items) => SavedPlacesApi(
  get: (_) async => {
    'items': items,
    'total': items.length,
    'offset': 0,
    'limit': 100,
  },
);

Map<String, dynamic> savedPlaceJson() => {
  'place_id': 12,
  'name': '광주실감콘텐츠큐브',
  'address': '광주광역시',
  'road_address': null,
  'latitude': 35.1107137,
  'longitude': 126.8778041,
  'created_at': '2026-10-08T00:00:00Z',
};

void main() {
  testWidgets('shows places returned from the saved places API without a records tab', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: SavedScreen(savedPlacesApi: responseApi([savedPlaceJson()]))),
    );
    await tester.pumpAndSettle();

    expect(find.text('가보고 싶은 곳'), findsOneWidget);
    expect(find.text('광주실감콘텐츠큐브'), findsOneWidget);
    expect(find.text('내 기록'), findsNothing);
  });

  testWidgets('shows an empty state for an empty saved places list', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SavedScreen(savedPlacesApi: responseApi(const []))),
    );
    await tester.pumpAndSettle();

    expect(find.text('저장한 장소가 없어요.'), findsOneWidget);
  });
}
