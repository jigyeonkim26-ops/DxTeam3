import 'package:flutter_test/flutter_test.dart';
import 'package:overlap_app/features/map/models/kakao_place_search_result.dart';

void main() {
  group('KakaoPlaceSearchResult.fromJson', () {
    test('parses the backend response and numeric coordinates', () {
      final result = KakaoPlaceSearchResult.fromJson({
        'kakao_place_id': '123',
        'name': '샘플 장소',
        'address': '서울시',
        'latitude': 37.5,
        'longitude': 127,
        'place_url': 'https://place.invalid/123',
      });

      expect(result.kakaoPlaceId, '123');
      expect(result.name, '샘플 장소');
      expect(result.latitude, 37.5);
      expect(result.longitude, 127.0);
    });

    test('parses coordinates returned as strings', () {
      final result = KakaoPlaceSearchResult.fromJson({
        'kakao_place_id': '123',
        'name': '샘플 장소',
        'address': '서울시',
        'latitude': '37.5',
        'longitude': '127.0',
        'place_url': 'https://place.invalid/123',
      });

      expect(result.latitude, 37.5);
      expect(result.longitude, 127.0);
    });

    test('throws a clear format error for missing required fields', () {
      expect(
        () => KakaoPlaceSearchResult.fromJson({'name': '샘플 장소'}),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('kakao_place_id'),
          ),
        ),
      );
    });
  });
}
