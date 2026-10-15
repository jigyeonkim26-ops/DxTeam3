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
  test('refresh requests use one unified backend session', () async {
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
    expect(paths, [
      '/ai/recommendations',
      '/ai/recommendations?refresh=true',
      '/ai/recommendations?refresh=true',
    ]);
  });

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

      expect(paths, ['/ai/recommendations', '/ai/recommendations']);
    },
  );

  test(
    'pending unified request is isolated across authenticated users',
    () async {
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

      final firstUserRequest = api.load();
      ApiTransport.setAccessToken('pending-second-user');
      final secondUserRequest = api.load();

      expect(paths, ['/ai/recommendations', '/ai/recommendations']);
      gates[1].complete({'recommendations': <dynamic>[]});
      await secondUserRequest;
      gates[0].complete({'recommendations': <dynamic>[]});
      await firstUserRequest;

      final nextRequest = api.load();
      expect(paths.last, '/ai/recommendations?refresh=true');
      gates[2].complete({'recommendations': <dynamic>[]});
      await nextRequest;
    },
  );

  test(
    'first call has no category or refresh and following call refreshes',
    () async {
      final paths = <String>[];
      final api = AiRecommendationsApi(
        get: (path, {responseTimeout}) async {
          paths.add(path);
          return {'recommendations': <dynamic>[]};
        },
      );

      await api.load();
      await api.load();

      expect(Uri.parse(paths.first).queryParameters, isEmpty);
      expect(Uri.parse(paths.last).queryParameters, {'refresh': 'true'});
    },
  );

  test('concurrent calls merge into one pending unified request', () async {
    final paths = <String>[];
    final gate = Completer<Map<String, dynamic>>();
    final api = AiRecommendationsApi(
      get: (path, {responseTimeout}) {
        paths.add(path);
        return gate.future;
      },
    );

    final first = api.load();
    final same = api.load();
    expect(paths, ['/ai/recommendations']);
    gate.complete({'recommendations': <dynamic>[]});
    await Future.wait([first, same]);
    expect(paths, hasLength(1));
  });
}
