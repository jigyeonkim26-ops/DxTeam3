import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  static String? _accessToken;
  static final sessionRevision = ValueNotifier<int>(0);

  static String? get accessToken => _accessToken;

  static void setAccessToken(String token) {
    if (_accessToken == token) return;
    _accessToken = token;
    sessionRevision.value++;
  }

  static Future<void> checkHealth() async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/health');
    try {
      await http.get(uri).timeout(const Duration(seconds: 5));
    } catch (_) {
      // Health check is best-effort; never log request data or exception details.
    }
  }

  static Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String nickname,
    required String birthDate,
    required String gender,
    required bool termsAccepted,
  }) async {
    final response = await _send(
      'POST',
      '/auth/register',
      body: {
        'email': email.trim().toLowerCase(),
        'password': password,
        'nickname': nickname.trim(),
        'birth_date': birthDate,
        'gender': gender,
        'terms_accepted': termsAccepted,
      },
    );
    return _decodeObject(response);
  }

  static Future<void> login({
    required String email,
    required String password,
  }) async {
    final response = await _send(
      'POST',
      '/auth/login',
      body: {'email': email.trim().toLowerCase(), 'password': password},
    );
    final payload = _decodeObject(response);
    final token = payload['access_token'];
    if (token is! String || token.isEmpty) {
      throw const ApiException('로그인 응답을 확인할 수 없습니다. 잠시 후 다시 시도해 주세요.');
    }
    setAccessToken(token);
  }

  static Future<Map<String, dynamic>> me() async {
    final token = _accessToken;
    if (token == null) {
      throw const ApiException('로그인이 필요합니다.', statusCode: 401);
    }
    final response = await _send(
      'GET',
      '/auth/me',
      headers: {'Authorization': 'Bearer $token'},
    );
    return _decodeObject(response);
  }

  static Future<http.Response> searchPlaces(String query) async {
    final token = _accessToken;
    if (token == null || token.isEmpty) {
      throw const ApiException('로그인이 필요합니다.', statusCode: 401);
    }
    final uri = Uri.parse('${ApiConfig.baseUrl}/places/search')
        .replace(queryParameters: {'query': query});
    try {
      final response = await http
          .get(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      }
      throw ApiException(
        '장소 검색 요청을 처리하지 못했습니다.',
        statusCode: response.statusCode,
      );
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException('네트워크에 연결할 수 없습니다. 연결 상태를 확인하고 다시 시도해 주세요.');
    }
  }

  static void clearSession() {
    _accessToken = null;
    sessionRevision.value++;
  }

  static Future<http.Response> _send(
    String method,
    String path, {
    Map<String, String>? headers,
    Map<String, Object?>? body,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    try {
      final requestHeaders = <String, String>{
        'Content-Type': 'application/json',
        ...?headers,
      };
      final response = switch (method) {
        'GET' =>
          await http
              .get(uri, headers: requestHeaders)
              .timeout(const Duration(seconds: 10)),
        'POST' =>
          await http
              .post(uri, headers: requestHeaders, body: jsonEncode(body))
              .timeout(const Duration(seconds: 10)),
        _ => throw const ApiException('지원하지 않는 요청입니다.'),
      };
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      }
      throw ApiException(
        _messageForStatus(response.statusCode, response.body),
        statusCode: response.statusCode,
      );
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException('서버에 연결할 수 없습니다. 네트워크와 백엔드 실행 상태를 확인해 주세요.');
    }
  }

  static Map<String, dynamic> _decodeObject(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Return the same safe, user-facing error for malformed responses.
    }
    throw const ApiException('서버 응답을 읽을 수 없습니다. 잠시 후 다시 시도해 주세요.');
  }

  static String _messageForStatus(int status, String body) {
    if (status == 401) return '이메일 또는 비밀번호가 올바르지 않습니다.';
    if (status == 409) return '이미 가입된 이메일입니다. 로그인해 주세요.';
    if (status == 422) {
      try {
        final detail = (jsonDecode(body) as Map<String, dynamic>)['detail'];
        if (detail is List && detail.isNotEmpty && detail.first is Map) {
          final item = detail.first as Map;
          final location = item['loc'];
          final field = location is List && location.isNotEmpty
              ? location.last.toString()
              : '';
          return switch (field) {
            'email' => '이메일 주소를 다시 확인해 주세요.',
            'password' => '비밀번호는 8~128자로 입력해 주세요.',
            'nickname' => '닉네임은 공백을 제외하고 1~50자로 입력해 주세요.',
            'birth_date' => '실제 존재하는 생년월일을 입력해 주세요. 미래 날짜는 사용할 수 없습니다.',
            'gender' => '성별을 다시 선택해 주세요.',
            'terms_accepted' => '필수 약관에 동의해 주세요.',
            _ => '입력한 내용을 다시 확인해 주세요.',
          };
        }
      } catch (_) {
        // Use a safe fallback for unexpected validation response shapes.
      }
      return '입력한 내용을 다시 확인해 주세요.';
    }
    return '요청을 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.';
  }
}
