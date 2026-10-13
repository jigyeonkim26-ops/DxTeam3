import 'package:flutter_test/flutter_test.dart';
import 'package:overlap_app/features/ai/services/ai_recommendations_api.dart';

Map<String, dynamic> recommendation(String id) => {
  'kakao_place_id': id,
  'rank': 1,
  'name': 'Verified $id',
  'address': 'Test district',
  'latitude': 35.0,
  'longitude': 126.0,
  'match_score': 0.9,
  'matched_keywords': ['quiet'],
  'reason': 'Matches the user preference',
  'source_url': 'https://place.map.kakao.com/$id',
};

void main() {
  test(
    'later recommendation requests exclude previously shown Kakao IDs',
    () async {
      final paths = <String>[];
      var call = 0;
      final api = AiRecommendationsApi(
        get: (path, {responseTimeout}) async {
          paths.add(path);
          call++;
          return {
            'recommendations': [
              recommendation(call == 1 || call == 3 ? '12345' : '23456'),
            ],
          };
        },
      );

      expect((await api.load()).single.kakaoPlaceId, '12345');
      expect((await api.load()).single.kakaoPlaceId, '23456');
      expect((await api.load()).single.kakaoPlaceId, '12345');
      expect(paths.first, '/ai/recommendations');
      final refresh = Uri.parse(paths.last);
      expect(refresh.path, '/ai/recommendations');
      expect(refresh.queryParameters['exclude_place_ids'], '12345,23456');
      expect(refresh.queryParameters['previous_place_ids'], '23456');
    },
  );
}
