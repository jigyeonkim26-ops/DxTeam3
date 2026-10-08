import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:overlap_app/features/map/services/map_places_api.dart';

void main() {
  test('maps record_count to recordCount and preserves a valid place', () async {
    final api = MapPlacesApi(
      request: () async => http.Response(
        jsonEncode([
          {
            'place_id': 12,
            'name': '광주CGI센터',
            'address': '광주광역시',
            'latitude': 35.1107137,
            'longitude': 126.8778041,
            'record_count': 3,
          },
        ]),
        200,
      ),
    );

    final places = await api.load();
    expect(places, hasLength(1));
    expect(places.single.id, '12');
    expect(places.single.recordCount, 3);
  });

  test('keeps one marker for duplicate place_id values', () async {
    final api = MapPlacesApi(
      request: () async => http.Response(
        jsonEncode([
          {
            'place_id': 12,
            'name': '첫 장소',
            'latitude': 35.1,
            'longitude': 126.8,
            'record_count': 2,
          },
          {
            'place_id': 12,
            'name': '중복 장소',
            'latitude': 35.2,
            'longitude': 126.9,
            'record_count': 9,
          },
        ]),
        200,
      ),
    );

    final places = await api.load();
    expect(places, hasLength(1));
    expect(places.single.name, '첫 장소');
  });

  test('accepts an empty API array', () async {
    final api = MapPlacesApi(request: () async => http.Response('[]', 200));

    expect(await api.load(), isEmpty);
  });

  test('drops entries with invalid coordinates', () async {
    final api = MapPlacesApi(
      request: () async => http.Response(
        jsonEncode([
          {
            'place_id': 1,
            'name': '잘못된 위도',
            'latitude': 91,
            'longitude': 126.8,
            'record_count': 1,
          },
          {
            'place_id': 2,
            'name': '잘못된 경도',
            'latitude': 35.1,
            'longitude': 'NaN',
            'record_count': 1,
          },
        ]),
        200,
      ),
    );

    expect(await api.load(), isEmpty);
  });

  test('reports HTTP failures without exposing a response body', () async {
    final api = MapPlacesApi(
      request: () async => http.Response('sensitive body', 401),
    );

    await expectLater(
      api.load(),
      throwsA(
        isA<MapPlacesApiException>().having(
          (error) => error.kind,
          'kind',
          MapPlacesApiErrorKind.unauthorized,
        ),
      ),
    );
  });
}
