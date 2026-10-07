import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:overlap_app/core/network/api_client.dart';
import 'package:overlap_app/features/map/screens/place_search_screen.dart';
import 'package:overlap_app/features/map/services/place_search_api.dart';

void main() {
  testWidgets('shows a successful result and ends the loading state', (
    tester,
  ) async {
    final screen = _screen(
      PlaceSearchApi(request: (_) async => _response([_result('새 장소')])),
    );
    await tester.pumpWidget(screen);

    await _search(tester, '새 장소');

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('새 장소'), findsNWidgets(2));
    expect(find.text('서울 테스트 주소'), findsOneWidget);
  });

  testWidgets('shows the empty result message for an empty response', (
    tester,
  ) async {
    await tester.pumpWidget(
      _screen(PlaceSearchApi(request: (_) async => http.Response('[]', 200))),
    );

    await _search(tester, '없는 장소');

    expect(find.text('검색 결과가 없어요.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows an error and retries successfully', (tester) async {
    var attempts = 0;
    final api = PlaceSearchApi(
      request: (_) async {
        attempts++;
        if (attempts == 1) {
          throw const ApiException('safe', statusCode: 500);
        }
        return _response([_result('재시도 장소')]);
      },
    );
    await tester.pumpWidget(_screen(api));

    await _search(tester, '재시도 장소');

    expect(find.text('장소 검색 중 서버 오류가 발생했습니다.'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    expect(find.text('재시도 장소'), findsNWidgets(2));
  });

  testWidgets('ignores an older response after a newer query succeeds', (
    tester,
  ) async {
    final olderResponse = Completer<http.Response>();
    final newerResponse = Completer<http.Response>();
    final api = PlaceSearchApi(
      request: (query) =>
          query == '이전 검색' ? olderResponse.future : newerResponse.future,
    );
    await tester.pumpWidget(_screen(api));

    await tester.enterText(find.byType(TextField), '이전 검색');
    await tester.pump(const Duration(milliseconds: 401));
    await tester.enterText(find.byType(TextField), '최신 검색');
    await tester.pump(const Duration(milliseconds: 401));

    newerResponse.complete(_response([_result('최신 결과')]));
    await tester.pump();
    await tester.pump();
    expect(find.text('최신 결과'), findsOneWidget);

    olderResponse.complete(_response([_result('이전 결과')]));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('최신 결과'), findsOneWidget);
    expect(find.text('이전 결과'), findsNothing);
  });
}

Widget _screen(PlaceSearchApi api) =>
    MaterialApp(home: PlaceSearchScreen(searchApi: api));

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pump(const Duration(milliseconds: 401));
  tester.testTextInput.hide();
  await tester.pumpAndSettle();
}

http.Response _response(List<Map<String, Object>> results) =>
    http.Response.bytes(
      utf8.encode(jsonEncode(results)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Map<String, Object> _result(String name) => {
  'kakao_place_id': name,
  'name': name,
  'address': '서울 테스트 주소',
  'latitude': 37.5,
  'longitude': 127.0,
  'place_url': 'https://place.invalid/test',
};
