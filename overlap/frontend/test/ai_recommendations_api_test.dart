import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:overlap_app/core/network/api_transport.dart';
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
    'refresh requests use backend suitability session and preserve first call',
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
      expect(paths.first, '/ai/recommendations?category=all');
      final refresh = Uri.parse(paths.last);
      expect(refresh.path, '/ai/recommendations');
      expect(refresh.queryParameters, {'category': 'all', 'refresh': 'true'});
    },
  );

  test(
    'changing authenticated user starts a fresh recommendation history',
    () async {
      final paths = <String>[];
      final api = AiRecommendationsApi(
        get: (path, {responseTimeout}) async {
          paths.add(path);
          return {
            'recommendations': [recommendation('12345')],
          };
        },
      );
      ApiTransport.setAccessToken('first-user-token');
      addTearDown(ApiTransport.clearAccessToken);

      await api.load();
      ApiTransport.setAccessToken('second-user-token');
      await api.load();

      expect(paths, [
        '/ai/recommendations?category=all',
        '/ai/recommendations?category=all',
      ]);
    },
  );

  test('pending requests are not shared across authenticated users', () async {
    final paths = <String>[];
    final gates = <Completer<Map<String, dynamic>>>[];
    final api = AiRecommendationsApi(
      get: (path, {responseTimeout}) {
        paths.add(path);
        final gate = Completer<Map<String, dynamic>>();
        gates.add(gate);
        return gate.future;
      },
    );
    ApiTransport.setAccessToken('pending-first-user');
    addTearDown(ApiTransport.clearAccessToken);

    final firstUserRequest = api.load(category: 'cafe');
    ApiTransport.setAccessToken('pending-second-user');
    final secondUserRequest = api.load(category: 'cafe');

    expect(paths, [
      '/ai/recommendations?category=cafe',
      '/ai/recommendations?category=cafe',
    ]);
    gates[1].complete({'recommendations': <dynamic>[]});
    await secondUserRequest;
    gates[0].complete({'recommendations': <dynamic>[]});
    await firstUserRequest;

    final nextSecondUserRequest = api.load(category: 'cafe');
    expect(Uri.parse(paths.last).queryParameters, {
      'category': 'cafe',
      'refresh': 'true',
    });
    gates[2].complete({'recommendations': <dynamic>[]});
    await nextSecondUserRequest;
  });

  test(
    'first request for each category omits refresh and category is exact',
    () async {
      final paths = <String>[];
      final api = AiRecommendationsApi(
        get: (path, {responseTimeout}) async {
          paths.add(path);
          return {'recommendations': <dynamic>[]};
        },
      );

      for (final category in AiRecommendationsApi.supportedCategories) {
        await api.load(category: category);
      }

      expect(
        paths.map((path) => Uri.parse(path).queryParameters),
        everyElement(
          predicate<Map<String, String>>(
            (query) =>
                query.length == 1 &&
                query.containsKey('category') &&
                query['category'] != null &&
                query['refresh'] == null,
          ),
        ),
      );
      expect(
        paths
            .map((path) => Uri.parse(path).queryParameters['category'])
            .toSet(),
        AiRecommendationsApi.supportedCategories,
      );
    },
  );

  test('switching back to a visited category requests its next page', () async {
    final paths = <String>[];
    final api = AiRecommendationsApi(
      get: (path, {responseTimeout}) async {
        paths.add(path);
        return {'recommendations': <dynamic>[]};
      },
    );

    await api.load(category: 'cafe');
    await api.load(category: 'bar');
    await api.load(category: 'cafe');

    expect(paths.map((path) => Uri.parse(path).queryParameters).toList(), [
      {'category': 'cafe'},
      {'category': 'bar'},
      {'category': 'cafe', 'refresh': 'true'},
    ]);
  });

  test('concurrent requests merge only within the same category', () async {
    final paths = <String>[];
    final gates = <String, Completer<Map<String, dynamic>>>{};
    final api = AiRecommendationsApi(
      get: (path, {responseTimeout}) {
        paths.add(path);
        final category = Uri.parse(path).queryParameters['category']!;
        return (gates[category] ??= Completer<Map<String, dynamic>>()).future;
      },
    );

    final firstCafe = api.load(category: 'cafe');
    final sameCafe = api.load(category: 'cafe');
    final bar = api.load(category: 'bar');
    expect(paths, [
      '/ai/recommendations?category=cafe',
      '/ai/recommendations?category=bar',
    ]);
    gates['cafe']!.complete({'recommendations': <dynamic>[]});
    gates['bar']!.complete({'recommendations': <dynamic>[]});
    await Future.wait([firstCafe, sameCafe, bar]);
  });
}
