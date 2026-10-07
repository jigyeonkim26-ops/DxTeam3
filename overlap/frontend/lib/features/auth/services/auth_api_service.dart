import '../../../core/network/api_transport.dart';

abstract final class AuthApiService {
  static Future<void> login({
    required String email,
    required String password,
  }) async {
    final dynamic response;
    try {
      response = await ApiTransport.post(
        '/auth/login',
        body: {'email': email.trim().toLowerCase(), 'password': password},
      );
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        throw const ApiException('이메일 또는 비밀번호가 올바르지 않습니다.', statusCode: 401);
      }
      rethrow;
    }
    if (response is! Map<String, dynamic> ||
        response['access_token'] is! String ||
        (response['access_token'] as String).isEmpty) {
      throw const ApiException('로그인 응답을 확인할 수 없습니다.');
    }
    ApiTransport.setAccessToken(response['access_token'] as String);
  }

  static Future<void> register({
    required String email,
    required String password,
    required String nickname,
    required String birthDate,
    required String gender,
  }) async {
    await ApiTransport.post(
      '/auth/register',
      body: {
        'email': email.trim().toLowerCase(),
        'password': password,
        'nickname': nickname.trim(),
        'birth_date': birthDate,
        'gender': gender,
        'terms_accepted': true,
      },
    );
  }
}
