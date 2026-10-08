import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:overlap_app/core/network/api_client.dart';
import 'package:overlap_app/features/map/services/place_search_api.dart';

void main() {
  test(
    'returns an empty list for an empty JSON array without network access',
    () async {
      final api = PlaceSearchApi(
        request: (_) async => http.Response('[]', 200),
      );

      expect(await api.search('장소'), isEmpty);
    },
  );

  test('maps a successful JSON array to result models', () async {
    final api = PlaceSearchApi(
      request: (_) async => http.Response(
        jsonEncode([
          {
            'kakao_place_id': '1',
            'name': '카페',
            'address': '서울',
            'latitude': '37.5',
            'longitude': 127,
            'place_url': 'https://place.invalid/1',
          },
        ]),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );

    final results = await api.search('카페');
    expect(results, hasLength(1));
    expect(results.single.name, '카페');
    expect(results.single.longitude, 127.0);
  });

  test('reports malformed response data safely', () async {
    final api = PlaceSearchApi(
      request: (_) async => http.Response('{"unexpected":true}', 200),
    );

    await expectLater(
      api.search('장소'),
      throwsA(
        isA<PlaceSearchException>().having(
          (error) => error.kind,
          'kind',
          PlaceSearchErrorKind.invalidResponse,
        ),
      ),
    );
  });

  test('classifies authentication and server failures', () async {
    final unauthorized = PlaceSearchApi(
      request: (_) async => throw const ApiException('safe', statusCode: 401),
    );
    final serverError = PlaceSearchApi(
      request: (_) async => throw const ApiException('safe', statusCode: 500),
    );

    await expectLater(
      unauthorized.search('장소'),
      throwsA(
        isA<PlaceSearchException>().having(
          (error) => error.kind,
          'kind',
          PlaceSearchErrorKind.unauthorized,
        ),
      ),
    );
    await expectLater(
      serverError.search('장소'),
      throwsA(
        isA<PlaceSearchException>().having(
          (error) => error.kind,
          'kind',
          PlaceSearchErrorKind.server,
        ),
      ),
    );
  });
}
