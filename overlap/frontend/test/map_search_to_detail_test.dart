import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:overlap_app/features/map/screens/map_screen.dart';
import 'package:overlap_app/features/map/services/map_places_api.dart';
import 'package:overlap_app/features/map/services/place_search_api.dart';
import 'package:overlap_app/features/map/widgets/map_view.dart';
import 'package:overlap_app/features/memory/services/record_api.dart';
import 'package:overlap_app/features/user/services/saved_places_api.dart';

void main() {
  testWidgets(
    'ordinary Kakao search opens map preview and common detail without AI content',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final records = RecordApi(
        tokenProvider: () => 'offline-token',
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({'items': [], 'total': 0}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      addTearDown(records.close);
      final search = PlaceSearchApi(
        request: (_) async => http.Response.bytes(
          utf8.encode(
            jsonEncode([
              {
                'kakao_place_id': '12345',
                'name': '검증된 공원',
                'address': '서울시 테스트로 1',
                'latitude': 37.5,
                'longitude': 127.0,
                'place_url': 'https://place.map.kakao.com/12345',
              },
            ]),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MapScreen(
              mapPlacesApi: MapPlacesApi(
                request: () async => http.Response('[]', 200),
              ),
              placeSearchApi: search,
              placeRecordApi: records,
              savedPlacesApi: SavedPlacesApi(
                get: (_) async => {
                  'place_id': null,
                  'saved': false,
                  'record_count': 0,
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('장소 또는 주소 검색'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '공원');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      await tester.tap(find.text('검증된 공원').last);
      await tester.pump();
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final focus = tester.widget<MapView>(find.byType(MapView)).searchPlace;
      expect(focus?.id, '12345');
      expect(focus?.latitude, 37.5);
      expect(find.text('장소 상세 보기'), findsOneWidget);
      expect(find.text('AI 추천 장소'), findsNothing);
      expect(tester.getCenter(find.text('장소 상세 보기')).dy, lessThan(1200));
      await tester.tap(find.text('장소 상세 보기'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('검증된 공원'), findsOneWidget);
      expect(find.text('서울시 테스트로 1'), findsOneWidget);
      expect(find.text('AI 추천 이유'), findsNothing);
      expect(find.text('이 장소에 아직 기록이 없어요.'), findsOneWidget);
    },
  );
}
