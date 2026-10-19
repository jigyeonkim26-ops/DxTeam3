import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

enum ApiExceptionKind { http, network, timeout }

class ApiException implements Exception {
  const ApiException(
    this.message, {
    this.statusCode,
    this.kind = ApiExceptionKind.http,
  });

  final String message;
  final int? statusCode;
  final ApiExceptionKind kind;

  @override
  String toString() => message;
}

class ApiClient {
  static String? _accessToken;
  static String? _sessionIdentity;
  static int _sessionIdentityCounter = 0;
  static bool _sessionExpired = false;
  static Future<bool>? _refreshInFlight;
  static const _storage = FlutterSecureStorage();
  static const _refreshStorageKey = 'overlap.refresh_token.v1';
  static Future<String?> Function() _readStoredRefreshToken = () =>
      _storage.read(key: _refreshStorageKey);
  static Future<void> Function(String) _writeStoredRefreshToken = (value) =>
      _storage.write(key: _refreshStorageKey, value: value);
  static Future<void> Function() _deleteStoredRefreshToken = () =>
      _storage.delete(key: _refreshStorageKey);
  static Future<http.Response> Function(Uri, String) _postRefresh =
      (uri, value) => http.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': value}),
      );
  static Future<http.Response> Function(Uri)? _getAuthenticatedOverride;
  static final sessionRevision = ValueNotifier<int>(0);

  static String? get accessToken => _accessToken;
  static bool get sessionExpired => _sessionExpired;
  static String? get sessionIdentity => _sessionIdentity;

  static String _newSessionIdentity() =>
      '${DateTime.now().microsecondsSinceEpoch}-${++_sessionIdentityCounter}';

  static void setAccessToken(String token) {
    if (_accessToken == token && !_sessionExpired) return;
    _accessToken = token;
    _sessionIdentity = _newSessionIdentity();
    _sessionExpired = false;
    sessionRevision.value++;
  }

  static Future<void> establishSession({
    required String accessToken,
    required String refreshToken,
    String? sessionIdentity,
  }) async {
    await _writeStoredRefreshToken(refreshToken);
    _accessToken = accessToken;
    _sessionExpired = false;
    _sessionIdentity = sessionIdentity ?? _newSessionIdentity();
    sessionRevision.value++;
  }

  /// Installs rotated credentials without changing the user's logical session.
  static Future<void> replaceSessionTokens({
    required String accessToken,
    required String refreshToken,
    String? sessionIdentity,
  }) async {
    await _writeStoredRefreshToken(refreshToken);
    final restoring = _accessToken == null || _sessionExpired;
    _accessToken = accessToken;
    _sessionExpired = false;
    _sessionIdentity ??= sessionIdentity ?? _newSessionIdentity();
    if (restoring) sessionRevision.value++;
  }

  static Future<bool> refreshSession() {
    final running = _refreshInFlight;
    if (running != null) return running;
    final operation = _refreshSessionOnce();
    _refreshInFlight = operation;
    return operation.whenComplete(() => _refreshInFlight = null);
  }

  static Future<bool> _refreshSessionOnce() async {
    final String? refreshToken;
    try {
      refreshToken = await _readStoredRefreshToken();
    } catch (_) {
      throw const ApiException(
        '보안 저장소에서 로그인 정보를 읽지 못했습니다. 다시 시도해 주세요.',
        kind: ApiExceptionKind.network,
      );
    }
    if (refreshToken == null || refreshToken.isEmpty) return false;
    final uri = Uri.parse('${ApiConfig.baseUrl}/auth/refresh');
    try {
      final response = await _postRefresh(
        uri,
        refreshToken,
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode == 401) {
        await clearPersistedRefreshToken();
        expireSession();
        return false;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          '세션 복구를 일시적으로 완료하지 못했습니다. 다시 시도해 주세요.',
          statusCode: response.statusCode,
        );
      }
      final payload = _decodeObject(response);
      final access = payload['access_token'];
      final rotated = payload['refresh_token'];
      if (access is! String ||
          access.isEmpty ||
          rotated is! String ||
          rotated.isEmpty) {
        throw const ApiException('세션 복구 응답을 확인할 수 없습니다.');
      }
      await replaceSessionTokens(
        accessToken: access,
        refreshToken: rotated,
        sessionIdentity: payload['session_id'] as String?,
      );
      return true;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException(
        '네트워크에 연결할 수 없습니다. 연결 상태를 확인하고 다시 시도해 주세요.',
        kind: ApiExceptionKind.network,
      );
    }
  }

  static Future<void> clearPersistedRefreshToken() =>
      _deleteStoredRefreshToken();

  static Future<String?> readRefreshToken() => _readStoredRefreshToken();

  @visibleForTesting
  static void configureAuthForTesting({
    required Future<String?> Function() readRefreshToken,
    required Future<void> Function(String) writeRefreshToken,
    required Future<void> Function() deleteRefreshToken,
    required Future<http.Response> Function(Uri, String) postRefresh,
    Future<http.Response> Function(Uri)? getAuthenticated,
  }) {
    _readStoredRefreshToken = readRefreshToken;
    _writeStoredRefreshToken = writeRefreshToken;
    _deleteStoredRefreshToken = deleteRefreshToken;
    _postRefresh = postRefresh;
    _getAuthenticatedOverride = getAuthenticated;
  }

  @visibleForTesting
  static void resetAuthForTesting() {
    _readStoredRefreshToken = () => _storage.read(key: _refreshStorageKey);
    _writeStoredRefreshToken = (value) =>
        _storage.write(key: _refreshStorageKey, value: value);
    _deleteStoredRefreshToken = () => _storage.delete(key: _refreshStorageKey);
    _postRefresh = (uri, value) => http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'refresh_token': value}),
    );
    _getAuthenticatedOverride = null;
  }

  static Future<http.Response> sendAuthenticatedRequest(
    Future<http.Response> Function() send,
  ) async {
    var response = await send();
    if (response.statusCode != 401 || _accessToken == null) return response;
    final refreshed = await refreshSession();
    if (refreshed) {
      response = await send();
      if (response.statusCode != 401) return response;
    }
    expireSession();
    return response;
  }

  static Future<http.Response> authenticatedGet(Uri uri) {
    final override = _getAuthenticatedOverride;
    if (override != null) return override(uri);
    return sendAuthenticatedRequest(
      () => http
          .get(uri, headers: {'Authorization': 'Bearer ${_accessToken ?? ''}'})
          .timeout(const Duration(seconds: 20)),
    );
  }

  /// Clears an authenticated token after the server rejects it. The return
  /// value makes repeated simultaneous 401 responses a no-op.
  static bool expireSession() {
    if (_accessToken == null) return false;
    _accessToken = null;
    _sessionIdentity = null;
    _sessionExpired = true;
    sessionRevision.value++;
    return true;
  }

  static Future<void> checkHealth() async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/health');
    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      debugPrint('[API] health status=${response.statusCode}');
    } catch (error) {
      debugPrint('[API] health failed error_type=${error.runtimeType}');
      // Health check is best-effort; never log request data or exception text.
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
    final refreshToken = payload['refresh_token'];
    if (refreshToken is String && refreshToken.isNotEmpty) {
      await establishSession(
        accessToken: token,
        refreshToken: refreshToken,
        sessionIdentity: payload['session_id'] as String?,
      );
    } else {
      await clearPersistedRefreshToken();
      setAccessToken(token);
    }
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
      final response = await sendAuthenticatedRequest(
        () => http
            .get(
              uri,
              headers: {'Authorization': 'Bearer ${_accessToken ?? token}'},
            )
            .timeout(const Duration(seconds: 10)),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      }
      if (response.statusCode == 401) expireSession();
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
    if (_accessToken == null && !_sessionExpired) return;
    _accessToken = null;
    _sessionIdentity = null;
    _sessionExpired = false;
    sessionRevision.value++;
  }

  static Future<http.Response> _send(
    String method,
    String path, {
    Map<String, String>? headers,
    Map<String, Object?>? body,
    bool allowRefreshRetry = true,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}$path');
    try {
      final requestHeaders = <String, String>{
        'Content-Type': 'application/json',
        ...?headers,
      };
      if (path == '/auth/me' && _accessToken != null) {
        requestHeaders['Authorization'] = 'Bearer $_accessToken';
      }
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
      if (response.statusCode == 401 &&
          allowRefreshRetry &&
          path == '/auth/me' &&
          _accessToken != null) {
        if (await refreshSession()) {
          return await _send(
            method,
            path,
            body: body,
            allowRefreshRetry: false,
          );
        }
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response;
      }
      if (response.statusCode == 401 &&
          path != '/auth/login' &&
          path != '/auth/register' &&
          path != '/auth/refresh' &&
          path != '/auth/logout') {
        expireSession();
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
