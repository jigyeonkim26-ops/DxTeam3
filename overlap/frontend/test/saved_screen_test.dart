import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overlap_app/core/network/api_client.dart';
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
  testWidgets(
    'shows places returned from the saved places API without a records tab',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SavedScreen(savedPlacesApi: responseApi([savedPlaceJson()])),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('가보고 싶은 곳'), findsOneWidget);
      expect(find.text('광주실감콘텐츠큐브'), findsOneWidget);
      expect(find.text('내 기록'), findsNothing);
    },
  );

  testWidgets('shows an empty state for an empty saved places list', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: SavedScreen(savedPlacesApi: responseApi(const []))),
    );
    await tester.pumpAndSettle();

    expect(find.text('저장한 장소가 없어요.'), findsOneWidget);
  });

  testWidgets(
    'embedded saved screen omits a second app bar and unsaves in place',
    (tester) async {
      var items = [savedPlaceJson()..['name'] = 'Saved Park'];
      var deletePath = '';
      final api = SavedPlacesApi(
        get: (_) async => {
          'items': items,
          'total': items.length,
          'offset': 0,
          'limit': 100,
        },
        delete: (path) async {
          deletePath = path;
          items = [];
          return {'place_id': 12, 'saved': false, 'saved_count': 0};
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              children: [SavedScreen(embedded: true, savedPlacesApi: api)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Saved Park'), findsOneWidget);
      await tester.tap(find.byTooltip('저장 취소'));
      await tester.pumpAndSettle();

      expect(deletePath, '/places/12/saved');
      expect(find.text('Saved Park'), findsNothing);
      expect(find.text('저장한 장소가 없어요.'), findsOneWidget);
    },
  );

  testWidgets('saved place load errors can be retried', (tester) async {
    var attempts = 0;
    final api = SavedPlacesApi(
      get: (_) async {
        attempts++;
        if (attempts == 1) throw const ApiException('network error');
        return {
          'items': [savedPlaceJson()..['name'] = 'Retry Park'],
          'total': 1,
          'offset': 0,
          'limit': 100,
        };
      },
    );

    await tester.pumpWidget(
      MaterialApp(home: SavedScreen(savedPlacesApi: api)),
    );
    await tester.pumpAndSettle();
    expect(find.text('network error'), findsOneWidget);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('Retry Park'), findsOneWidget);
    expect(attempts, 2);
  });

  testWidgets('re-entering the parent tab reloads saved places', (
    tester,
  ) async {
    var attempts = 0;
    final api = SavedPlacesApi(
      get: (_) async {
        attempts++;
        return {
          'items': [savedPlaceJson()],
          'total': 1,
          'offset': 0,
          'limit': 100,
        };
      },
    );

    Widget screen(bool isActive) => MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            SavedScreen(
              key: const ValueKey('saved-screen'),
              embedded: true,
              isActive: isActive,
              savedPlacesApi: api,
            ),
          ],
        ),
      ),
    );

    await tester.pumpWidget(screen(false));
    await tester.pumpAndSettle();
    expect(attempts, 1);

    await tester.pumpWidget(screen(true));
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });
}
