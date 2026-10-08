import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:overlap_app/features/map/screens/place_detail_screen.dart';
import 'package:overlap_app/features/memory/services/record_api.dart';
import 'package:overlap_app/features/memory/widgets/record_card.dart';
import 'package:overlap_app/features/user/services/saved_places_api.dart';

RecordApi responseApi(Map<String, dynamic> page) => RecordApi(
  tokenProvider: () => 'token',
  client: MockClient((request) async {
    expect(request.url.path, '/feed');
    expect(request.url.queryParameters['place_id'], '12');
    return http.Response(
      jsonEncode(page),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }),
);

SavedPlacesApi savedApi({bool saved = false}) => SavedPlacesApi(
  get: (_) async => {'place_id': 12, 'saved': saved, 'saved_count': 0},
);

Widget detail(RecordApi api, {SavedPlacesApi? savedPlacesApi}) => MaterialApp(
  home: PlaceDetailScreen(
    placeId: '12',
    name: '광주실감콘텐츠큐브',
    address: '광주광역시',
    recordCount: 1,
    recordApi: api,
    savedPlacesApi: savedPlacesApi ?? savedApi(),
  ),
);

void main() {
  testWidgets('renders records returned for the selected place', (tester) async {
    final api = responseApi({
      'items': [
        {
          'id': 1,
          'author': {'id': 7, 'name': '작성자'},
          'place': {
            'id': 12,
            'name': '광주실감콘텐츠큐브',
            'address': '광주광역시',
            'latitude': 35.1,
            'longitude': 126.8,
          },
          'created_at': '2026-10-07T00:00:00Z',
          'content': '실제 장소 기록',
          'emotion': 'good',
          'is_private': true,
          'photo_urls': [],
          'shared_groups': [],
        },
      ],
      'total': 1,
    });

    await tester.pumpWidget(detail(api));
    await tester.pumpAndSettle();

    expect(find.byType(RecordCard), findsOneWidget);
    expect(find.text('실제 장소 기록'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets('renders an empty state when the selected place has no records', (
    tester,
  ) async {
    final api = responseApi({'items': [], 'total': 0});

    await tester.pumpWidget(detail(api));
    await tester.pumpAndSettle();

    expect(find.text('이 장소에 아직 기록이 없어요.'), findsOneWidget);
    expect(find.byType(RecordCard), findsNothing);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets('loads saved state and updates the bookmark after save and unsave', (
    tester,
  ) async {
    var saved = false;
    final calls = <String>[];
    final placesApi = SavedPlacesApi(
      get: (path) async {
        calls.add('GET $path');
        return {'place_id': 12, 'saved': saved, 'saved_count': saved ? 1 : 0};
      },
      post: (path) async {
        calls.add('POST $path');
        saved = true;
        return {'place_id': 12, 'saved': true, 'saved_count': 1};
      },
      delete: (path) async {
        calls.add('DELETE $path');
        saved = false;
        return {'place_id': 12, 'saved': false, 'saved_count': 0};
      },
    );
    final api = responseApi({'items': [], 'total': 0});

    await tester.pumpWidget(detail(api, savedPlacesApi: placesApi));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);

    await tester.tap(find.byIcon(Icons.bookmark_border));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bookmark), findsOneWidget);

    await tester.tap(find.byIcon(Icons.bookmark));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    expect(calls, [
      'GET /places/12/saved',
      'POST /places/12/saved',
      'DELETE /places/12/saved',
    ]);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });
}
