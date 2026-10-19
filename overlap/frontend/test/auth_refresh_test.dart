import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:overlap_app/core/network/api_client.dart';

void main() {
  tearDown(() {
    ApiClient.resetAuthForTesting();
    ApiClient.clearSession();
  });

  test(
    'concurrent refresh calls share one rotation and preserve session identity',
    () async {
      var calls = 0;
      var stored = 'refresh-old';
      ApiClient.configureAuthForTesting(
        readRefreshToken: () async => stored,
        writeRefreshToken: (value) async {
          stored = value;
        },
        deleteRefreshToken: () async {
          stored = '';
        },
        postRefresh: (_, _) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 10));
          return http.Response(
            jsonEncode({
              'access_token': 'access-new',
              'refresh_token': 'refresh-new',
              'expires_in': 3600,
            }),
            200,
          );
        },
      );
      ApiClient.setAccessToken('access-old');
      final identity = ApiClient.sessionIdentity;

      final results = await Future.wait([
        ApiClient.refreshSession(),
        ApiClient.refreshSession(),
        ApiClient.refreshSession(),
      ]);

      expect(results, everyElement(isTrue));
      expect(calls, 1);
      expect(stored, 'refresh-new');
      expect(ApiClient.accessToken, 'access-new');
      expect(ApiClient.sessionIdentity, identity);
    },
  );

  test(
    'temporary server failure preserves refresh token and active session',
    () async {
      var deleted = false;
      ApiClient.configureAuthForTesting(
        readRefreshToken: () async => 'refresh-kept',
        writeRefreshToken: (_) async {},
        deleteRefreshToken: () async {
          deleted = true;
        },
        postRefresh: (_, _) async => http.Response('{}', 503),
      );
      ApiClient.setAccessToken('access-still-active');

      await expectLater(
        ApiClient.refreshSession(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.statusCode,
            'status',
            503,
          ),
        ),
      );
      expect(deleted, isFalse);
      expect(ApiClient.accessToken, 'access-still-active');
      expect(ApiClient.sessionExpired, isFalse);
    },
  );

  test(
    'definitively rejected refresh token is deleted and expires the session',
    () async {
      var deleted = false;
      ApiClient.configureAuthForTesting(
        readRefreshToken: () async => 'revoked-refresh',
        writeRefreshToken: (_) async {},
        deleteRefreshToken: () async {
          deleted = true;
        },
        postRefresh: (_, _) async => http.Response('{}', 401),
      );
      ApiClient.setAccessToken('old-access');

      expect(await ApiClient.refreshSession(), isFalse);
      expect(deleted, isTrue);
      expect(ApiClient.accessToken, isNull);
      expect(ApiClient.sessionExpired, isTrue);
    },
  );
}
