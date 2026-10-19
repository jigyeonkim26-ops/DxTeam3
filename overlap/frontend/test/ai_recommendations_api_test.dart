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
  setUp(AiRecommendationsApi.clearSessionCache);

  test('refresh requests use one unified backend session', () async {
    final paths = <String>[];
    var call = 0;
    final api = AiRecommendationsApi(
      get: (path, {responseTimeout}) async {
        paths.add(path);
        call++;
        return {
          'session_status': call == 1 ? 'available' : 'exhausted',
          'recommendations': [
            recommendation(call == 1 || call == 3 ? '12345' : '23456'),
          ],
        };
      },
    );

    expect((await api.load()).single.kakaoPlaceId, '12345');
    expect(api.sessionStatus, 'available');
    expect((await api.load()).single.kakaoPlaceId, '23456');
    expect(api.sessionStatus, 'exhausted');
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
    'restores cached page per account without issuing another request',
    () async {
      final paths = <String>[];
      ApiTransport.setAccessToken('cache-first-user');
      addTearDown(ApiTransport.clearAccessToken);
      final firstApi = AiRecommendationsApi(
        get: (path, {responseTimeout}) async {
          paths.add(path);
          return {
            'session_status': 'available',
            'recommendations': [recommendation('first-page')],
          };
        },
      );
      final first = await firstApi.load();

      final restoredApi = AiRecommendationsApi(
        get: (path, {responseTimeout}) async {
          paths.add(path);
          return {
            'recommendations': [recommendation('unexpected-network-call')],
          };
        },
      );
      expect((await restoredApi.load()).single.kakaoPlaceId, 'first-page');
      expect(
        restoredApi.firstRecommendations.single.kakaoPlaceId,
        'first-page',
      );
      expect(paths, ['/ai/recommendations']);

      ApiTransport.setAccessToken('cache-second-user');
      final secondApi = AiRecommendationsApi(
        get: (path, {responseTimeout}) async {
          paths.add(path);
          return {
            'recommendations': [recommendation('second-user-page')],
          };
        },
      );
      expect((await secondApi.load()).single.kakaoPlaceId, 'second-user-page');
      expect(paths, ['/ai/recommendations', '/ai/recommendations']);
      expect(first.single.kakaoPlaceId, 'first-page');
    },
  );

  test('restores complete session page history and current page', () async {
    final paths = <String>[];
    ApiTransport.setAccessToken('history-cache-user');
    addTearDown(ApiTransport.clearAccessToken);
    final api = AiRecommendationsApi(
      get: (path, {responseTimeout}) async {
        paths.add(path);
        final refresh = path.contains('refresh=true');
        if (!refresh) {
          return {
            'session_status': 'available',
            'recommendations': [recommendation('A')],
          };
        }
        if (paths.where((path) => path.contains('refresh=true')).length == 1) {
          return {
            'session_status': 'available',
            'recommendations': [recommendation('B')],
          };
        }
        return {'session_status': 'exhausted', 'recommendations': <dynamic>[]};
      },
    );
    await api.load();
    await api.load();
    await api.load();
    expect(api.recommendationPages.map((page) => page.single.kakaoPlaceId), [
      'A',
      'B',
    ]);
    expect(api.sessionStatus, 'exhausted');

    api.selectPage(0);
    final restored = AiRecommendationsApi(
      get: (path, {responseTimeout}) async {
        paths.add(path);
        return {'recommendations': <dynamic>[]};
      },
    );
    expect((await restored.load()).single.kakaoPlaceId, 'A');
    expect(restored.recommendationPages, hasLength(2));
    expect(restored.currentPageIndex, 0);
    expect(restored.sessionStatus, 'exhausted');
    expect(paths, [
      '/ai/recommendations',
      '/ai/recommendations?refresh=true',
      '/ai/recommendations?refresh=true',
    ]);
  });

  test(
    'preserves a three-place response and a partial one-place next page',
    () async {
      final paths = <String>[];
      final api = AiRecommendationsApi(
        get: (path, {responseTimeout}) async {
          paths.add(path);
          if (paths.length == 1) {
            return {
              'session_status': 'available',
              'recommendations': [
                recommendation('A'),
                recommendation('B'),
                recommendation('C'),
              ],
            };
          }
          return {
            'session_status': 'exhausted',
            'recommendations': [recommendation('D')],
          };
        },
      );

      expect((await api.load()).map((item) => item.kakaoPlaceId), [
        'A',
        'B',
        'C',
      ]);
      expect((await api.load()).map((item) => item.kakaoPlaceId), ['D']);
      expect(api.recommendationPages.map((page) => page.length), [3, 1]);
      expect(api.currentPageIndex, 1);
      api.selectPage(0);
      expect(
        (await AiRecommendationsApi().load()).map((item) => item.kakaoPlaceId),
        ['A', 'B', 'C'],
      );
      expect(paths, [
        '/ai/recommendations',
        '/ai/recommendations?refresh=true',
      ]);
    },
  );

  test('explicit new session clears old page history', () async {
    final paths = <String>[];
    ApiTransport.setAccessToken('new-session-user');
    addTearDown(ApiTransport.clearAccessToken);
    var page = 'A';
    final api = AiRecommendationsApi(
      get: (path, {responseTimeout}) async {
        paths.add(path);
        return {
          'recommendations': [recommendation(page)],
        };
      },
    );
    await api.load();
    page = 'B';
    await api.load();
    expect(api.recommendationPages, hasLength(2));

    api.startNewSession();
    page = 'NEW';
    expect((await api.load()).single.kakaoPlaceId, 'NEW');
    expect(api.recommendationPages, hasLength(1));
    expect(api.firstRecommendations.single.kakaoPlaceId, 'NEW');
    expect(paths, [
      '/ai/recommendations',
      '/ai/recommendations?refresh=true',
      '/ai/recommendations',
    ]);
  });

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
