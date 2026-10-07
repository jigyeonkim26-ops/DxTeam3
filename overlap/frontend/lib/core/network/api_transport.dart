import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'api_client.dart';
import 'api_config.dart';

export 'api_client.dart' show ApiException;

abstract final class ApiTransport {
  static const String baseUrl = ApiConfig.baseUrl;

  static String? get accessToken => ApiClient.accessToken;

  static void setAccessToken(String token) => ApiClient.setAccessToken(token);

  static void clearAccessToken() => ApiClient.clearSession();

  static Future<dynamic> get(String path) => _send('GET', path);

  static Future<dynamic> post(String path, {Object? body}) =>
      _send('POST', path, body: body);

  static Future<dynamic> put(String path, {Object? body}) =>
      _send('PUT', path, body: body);

  static Future<dynamic> patch(String path, {Object? body}) =>
      _send('PATCH', path, body: body);

  static Future<dynamic> delete(String path) => _send('DELETE', path);

  static Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.openUrl(method, Uri.parse('$baseUrl$path'));
      request.headers.contentType = ContentType.json;
      final token = accessToken;
      if (token != null) {
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }
      if (body != null) request.write(jsonEncode(body));

      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final responseBody = await utf8.decoder.bind(response).join();
      dynamic decoded;
      if (responseBody.isNotEmpty) {
        try {
          decoded = jsonDecode(responseBody);
        } on FormatException {
          throw const ApiException('서버 응답을 읽을 수 없습니다.');
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          _messageForStatus(response.statusCode, decoded),
          statusCode: response.statusCode,
        );
      }
      return decoded;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('서버 응답 시간이 초과되었습니다.');
    } on SocketException {
      throw const ApiException('서버에 연결할 수 없습니다. 백엔드 실행 상태를 확인해 주세요.');
    } on HttpException {
      throw const ApiException('서버와 통신할 수 없습니다.');
    } finally {
      client.close(force: true);
    }
  }

  static String _messageForStatus(int statusCode, dynamic body) {
    if (statusCode == 401) return '로그인이 필요하거나 로그인 시간이 만료되었습니다.';
    if (statusCode == 403) return '이 요청을 수행할 권한이 없습니다.';
    if (statusCode == 404) return '요청한 모임 또는 초대 코드를 찾을 수 없습니다.';
    if (statusCode == 409) return '이미 가입했거나 중복된 요청입니다.';
    if (statusCode == 422) return '입력한 내용을 확인해 주세요.';
    if (body is Map<String, dynamic> && body['detail'] is String) {
      return body['detail'] as String;
    }
    return '요청을 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.';
  }
}
