import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:overlap_app/features/map/widgets/kakao_map_webview.dart';
import 'package:overlap_app/features/group/services/group_api_service.dart';
import 'package:overlap_app/features/group/services/group_list_store.dart';
import 'package:overlap_app/features/memory/screens/record_compose_screen.dart';
import 'package:overlap_app/features/memory/services/record_api.dart';
import 'package:overlap_app/shared/models/place.dart';

import 'record_api_test.dart' show recordJson;

void main() {
  testWidgets(
    'map resolution replaces a searched place with real ID and saves without a new search',
    (tester) async {
      GroupListStore.replaceGroups(const []);
      addTearDown(GroupListStore.clear);
      const config = MethodChannel('overlap/kakao_config');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        config,
        (_) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          config,
          null,
        ),
      );
      var saves = 0;
      var published = false;
      final api = RecordApi(
        tokenProvider: () => 'token',
        client: MockClient((request) async {
          if (request.method == 'GET') return http.Response('[]', 200);
          saves++;
          final body = utf8.decode(request.bodyBytes, allowMalformed: true);
          expect(body, contains('"is_private":true'));
          expect(body, contains('"content":""'));
          expect(body, contains('"kakao_place_id":"456"'));
          expect(body, contains('"latitude":36.25'));
          expect(body, contains('"longitude":128.5'));
          expect(
            request.headers['content-type'],
            contains('multipart/form-data'),
          );
          return http.Response(
            jsonEncode(recordJson()),
            201,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      await tester.binding.setSurfaceSize(const Size(900, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecordComposeScreen(
              onExitToMap: () {},
              onPublished: () => published = true,
              recordApi: api,
              pickPhotos: (_) async => [
                XFile.fromData(
                  base64Decode(
                    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
                  ),
                  path: 'photo.png',
                ),
              ],
              pickPlace: (_) async => const Place(
                id: '123',
                name: '선택한 장소',
                latitude: 37,
                longitude: 127,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('기록 남기기'));
      await tester.tap(find.text('기록 남기기'));
      await tester.pumpAndSettle();
      expect(find.text('사진을 한 장 이상 추가해 주세요.'), findsOneWidget);
      expect(saves, 0);
      await tester.ensureVisible(find.text('갤러리'));
      await tester.tap(find.text('갤러리'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('좋아요'));
      await tester.tap(find.text('좋아요'));
      await tester.ensureVisible(find.text('장소를 선택해 주세요'));
      await tester.tap(find.text('장소를 선택해 주세요'));
      await tester.pumpAndSettle();
      final map = tester.widget<KakaoMapWebView>(find.byType(KakaoMapWebView));
      map.onLocationChanged!(36.25, 128.5);
      await tester.pumpAndSettle();
      expect(find.text('선택한 장소'), findsNothing);
      map.onPlaceResolved!(
        const KakaoPlaceSelection(
          latitude: 36.25,
          longitude: 128.5,
          placeName: '자동 조회 장소',
          buildingName: '',
          roadAddress: '도로명 주소',
          lotAddress: '',
          place: KakaoPlaceSearchResult(
            id: '456',
            placeName: '자동 조회 장소',
            categoryName: '',
            phone: '',
            roadAddress: '도로명 주소',
            address: '',
            latitude: 36.25,
            longitude: 128.5,
            distance: 0,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('자동 조회 장소'), findsOneWidget);
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('기록 남기기'));
      await tester.tap(find.text('기록 남기기'));
      await tester.pumpAndSettle();
      expect(saves, 1);
      expect(published, true);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );

  testWidgets('compose group picker follows the shared group store', (
    tester,
  ) async {
    GroupListStore.replaceGroups(const []);
    addTearDown(GroupListStore.clear);
    const config = MethodChannel('overlap/kakao_config');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      config,
      (_) async => null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        config,
        null,
      ),
    );
    final api = RecordApi(
      tokenProvider: () => 'token',
      client: MockClient((request) async => http.Response('[]', 200)),
    );
    addTearDown(api.close);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecordComposeScreen(onExitToMap: () {}, recordApi: api),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Fresh group'), findsNothing);

    GroupListStore.upsertGroup(
      const GroupApiItem(id: 99, name: 'Fresh group', memberCount: 1),
    );
    await tester.scrollUntilVisible(
      find.text('Fresh group'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Fresh group'), findsOneWidget);

    GroupListStore.removeGroupFromCache('99');
    await tester.pump();
    expect(find.text('Fresh group'), findsNothing);
  });
  for (final invalidId in <String?>[null, 'fake-coordinate-id']) {
    testWidgets(
      'unresolved or invalid ID ($invalidId) keeps address and blocks save; search fallback works',
      (tester) async {
        const config = MethodChannel('overlap/kakao_config');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          config,
          (_) async => null,
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            config,
            null,
          ),
        );
        await tester.binding.setSurfaceSize(const Size(900, 1800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var saves = 0;
        final api = RecordApi(
          tokenProvider: () => 'test-token',
          client: MockClient((request) async {
            if (request.method == 'GET') return http.Response('[]', 200);
            saves++;
            expect(
              utf8.decode(request.bodyBytes, allowMalformed: true),
              contains('"kakao_place_id":"789"'),
            );
            return http.Response(
              jsonEncode(recordJson()),
              201,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RecordComposeScreen(
                onExitToMap: () {},
                recordApi: api,
                pickPhotos: (_) async => [
                  XFile.fromData(
                    base64Decode(
                      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
                    ),
                    path: 'photo.png',
                  ),
                ],
                pickPlace: (_) async => const Place(
                  id: '789',
                  name: '검색으로 선택한 장소',
                  latitude: 35.1,
                  longitude: 126.8,
                  address: '검색 주소',
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('갤러리'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('좋아요'));
        await tester.pumpAndSettle();
        final map = tester.widget<KakaoMapWebView>(
          find.byType(KakaoMapWebView),
        );
        map.onLocationChanged!(35.1, 126.8);
        map.onPlaceResolved!(
          KakaoPlaceSelection(
            latitude: 35.1,
            longitude: 126.8,
            placeName: '',
            buildingName: '주소의 건물명',
            roadAddress: '주소만 확인됨',
            lotAddress: '',
            place: invalidId == null
                ? null
                : KakaoPlaceSearchResult(
                    id: invalidId,
                    placeName: '유효하지 않은 장소',
                    categoryName: '',
                    phone: '',
                    roadAddress: '',
                    address: '',
                    latitude: 35.1,
                    longitude: 126.8,
                    distance: 0,
                  ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('주소만 확인됨'), findsWidgets);
        expect(find.text('주변 장소를 찾지 못했어요. 장소 검색으로 선택해 주세요.'), findsOneWidget);
        await tester.ensureVisible(find.byType(SwitchListTile));
        await tester.tap(find.byType(SwitchListTile));
        await tester.ensureVisible(find.text('기록 남기기'));
        await tester.tap(find.text('기록 남기기'));
        await tester.pumpAndSettle();
        expect(saves, 0);
        expect(find.text('기록할 장소를 선택해 주세요.'), findsOneWidget);
        await tester.ensureVisible(find.text('장소를 선택해 주세요'));
        await tester.tap(find.text('장소를 선택해 주세요'));
        await tester.pumpAndSettle();
        expect(find.text('검색으로 선택한 장소'), findsOneWidget);
        final selectedMap = tester.widget<KakaoMapWebView>(
          find.byType(KakaoMapWebView),
        );
        expect(selectedMap.selectionRequest!.placeId, '789');
        await tester.ensureVisible(find.text('기록 남기기'));
        await tester.tap(find.text('기록 남기기'));
        await tester.pumpAndSettle();
        expect(saves, 1);
        await tester.pumpWidget(const SizedBox());
        api.close();
      },
    );
  }

  testWidgets(
    'initial map selection saves without opening search and ignores stale coordinates',
    (tester) async {
      const config = MethodChannel('overlap/kakao_config');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        config,
        (_) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          config,
          null,
        ),
      );
      await tester.binding.setSurfaceSize(const Size(900, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var searches = 0;
      var saves = 0;
      final api = RecordApi(
        tokenProvider: () => 'test-token',
        client: MockClient((request) async {
          if (request.method == 'GET') return http.Response('[]', 200);
          saves++;
          final body = utf8.decode(request.bodyBytes, allowMalformed: true);
          expect(body, contains('"kakao_place_id":"123456"'));
          expect(body, contains('"latitude":35.2001'));
          expect(body, contains('"longitude":126.9001'));
          expect(body, contains('"name":"광주CGI센터"'));
          return http.Response(
            jsonEncode(recordJson()),
            201,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecordComposeScreen(
              onExitToMap: () {},
              recordApi: api,
              pickPhotos: (_) async => [
                XFile.fromData(
                  base64Decode(
                    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
                  ),
                  path: 'photo.png',
                ),
              ],
              pickPlace: (_) async {
                searches++;
                return null;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final map = tester.widget<KakaoMapWebView>(find.byType(KakaoMapWebView));
      map.onLocationChanged!(35.1, 126.8);
      map.onLocationChanged!(35.2, 126.9);
      const place = KakaoPlaceSearchResult(
        id: '123456',
        placeName: '광주CGI센터',
        categoryName: '',
        phone: '',
        roadAddress: '테스트 도로명 주소',
        address: '',
        latitude: 35.2001,
        longitude: 126.9001,
        distance: 15,
      );
      map.onPlaceResolved!(
        const KakaoPlaceSelection(
          latitude: 35.1,
          longitude: 126.8,
          placeName: '광주CGI센터',
          buildingName: '',
          roadAddress: '',
          lotAddress: '',
          place: place,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('광주CGI센터'), findsNothing);
      map.onPlaceResolved!(
        const KakaoPlaceSelection(
          latitude: 35.2,
          longitude: 126.9,
          placeName: '광주CGI센터',
          buildingName: '',
          roadAddress: '',
          lotAddress: '',
          place: place,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('광주CGI센터'), findsOneWidget);
      expect(searches, 0);
      map.onLocationChanged!(35.3, 127.0);
      await tester.pumpAndSettle();
      expect(find.text('광주CGI센터'), findsNothing);
      map.onLocationChanged!(35.2, 126.9);
      map.onPlaceResolved!(
        const KakaoPlaceSelection(
          latitude: 35.2,
          longitude: 126.9,
          placeName: '광주CGI센터',
          buildingName: '',
          roadAddress: '',
          lotAddress: '',
          place: place,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('갤러리'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('좋아요'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(SwitchListTile));
      await tester.tap(find.byType(SwitchListTile));
      await tester.ensureVisible(find.text('기록 남기기'));
      await tester.tap(find.text('기록 남기기'));
      await tester.pumpAndSettle();
      expect(saves, 1);
      expect(searches, 0);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
}
