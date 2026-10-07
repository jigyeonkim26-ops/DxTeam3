import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:overlap_app/features/map/widgets/kakao_map_webview.dart';
import 'package:overlap_app/features/memory/screens/record_compose_screen.dart';
import 'package:overlap_app/features/memory/services/record_api.dart';
import 'package:overlap_app/shared/models/place.dart';

import 'record_api_test.dart' show recordJson;

void main() {
  testWidgets(
    'private compose requires photo emotion place but allows empty story',
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
          expect(body, contains('"kakao_place_id":"123"'));
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
}
