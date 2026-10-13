import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:overlap_app/features/group/services/group_list_store.dart';
import 'package:overlap_app/features/map/widgets/kakao_map_webview.dart';
import 'package:overlap_app/features/map/screens/place_detail_screen.dart';
import 'package:overlap_app/features/memory/services/record_api.dart';
import 'package:overlap_app/features/user/screens/profile_screen.dart';

import 'record_api_test.dart' show recordJson;

void main() {
  testWidgets(
    'profile map stays in the profile and contains only mine feed places',
    (tester) async {
      GroupListStore.replaceGroups(const []);
      addTearDown(GroupListStore.clear);
      final record = recordJson();
      final invalidRecord =
          jsonDecode(jsonEncode(record)) as Map<String, dynamic>;
      invalidRecord['id'] = 999;
      (invalidRecord['place'] as Map<String, dynamic>)
        ..['id'] = 999
        ..['latitude'] = 0
        ..['longitude'] = 0;
      final api = RecordApi(
        tokenProvider: () => 'offline-token',
        client: MockClient((request) async {
          expect(request.url.path, '/feed');
          if (request.url.queryParameters['place_id'] == null) {
            expect(request.url.queryParameters['mine'], 'true');
          }
          return http.Response(
            jsonEncode({
              'items': request.url.queryParameters['place_id'] == null
                  ? [record, invalidRecord]
                  : [record],
              'total': request.url.queryParameters['place_id'] == null ? 2 : 1,
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(api.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ProfileScreen(recordApi: api)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byIcon(Icons.map_outlined));
      await tester.pump();
      final map = tester.widget<KakaoMapWebView>(find.byType(KakaoMapWebView));
      expect(map.initialMapLevel, 13);
      expect(map.minimumBoundsLevel, 9);
      expect(map.places, hasLength(1));
      expect(map.places.single.id, '${(record['place'] as Map)['id']}');
      expect(find.byType(ProfileScreen), findsOneWidget);
      map.onPlaceTap!(map.places.single);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PlaceDetailScreen), findsOneWidget);
      Navigator.of(tester.element(find.byType(PlaceDetailScreen))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byIcon(Icons.grid_view_rounded));
      await tester.pump();
      expect(find.byType(KakaoMapWebView, skipOffstage: false), findsOneWidget);
    },
  );
}
