import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_config.dart';
import '../../../core/network/api_transport.dart';
import '../../user/models/user_profile.dart';

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

  static Future<UserProfile> currentUser() async {
    final response = await ApiTransport.get('/auth/me');
    return _profileFromResponse(response);
  }

  static Future<UserProfile> updateCurrentUser({
    String? nickname,
    String? birthDate,
    String? gender,
  }) async {
    final body = <String, dynamic>{};
    if (nickname != null) body['nickname'] = nickname.trim();
    if (birthDate != null) body['birth_date'] = birthDate;
    if (gender != null) body['gender'] = gender;
    if (body.isEmpty) {
      throw const ApiException('수정할 프로필 정보를 하나 이상 입력해 주세요.');
    }

    final response = await ApiTransport.patch('/auth/me', body: body);
    return _profileFromResponse(response);
  }

  static Future<void> uploadProfilePhoto(XFile photo) async {
    final token = _requireAccessToken();
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConfig.baseUrl}/auth/me/photo'),
      )..headers['Authorization'] = 'Bearer $token';
      request.files.add(
        http.MultipartFile.fromBytes(
          'photo',
          await photo.readAsBytes(),
          filename: photo.name,
        ),
      );
      final streamed = await request.send().timeout(
        const Duration(seconds: 20),
      );
      final response = await http.Response.fromStream(streamed)
          .timeout(const Duration(seconds: 20));
      _throwForPhotoResponse(response);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('프로필 사진 저장 시간이 초과되었습니다. 다시 시도해 주세요.');
    } catch (_) {
      throw const ApiException('프로필 사진을 저장하지 못했습니다. 네트워크 상태를 확인해 주세요.');
    }
  }

  static Future<void> deleteProfilePhoto() async {
    final token = _requireAccessToken();
    try {
      final response = await http
          .delete(
            Uri.parse('${ApiConfig.baseUrl}/auth/me/photo'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));
      _throwForPhotoResponse(response);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException('프로필 사진 삭제 시간이 초과되었습니다. 다시 시도해 주세요.');
    } catch (_) {
      throw const ApiException('프로필 사진을 삭제하지 못했습니다. 네트워크 상태를 확인해 주세요.');
    }
  }

  static String _requireAccessToken() {
    final token = ApiTransport.accessToken;
    if (token == null || token.isEmpty) {
      throw const ApiException('로그인이 필요합니다.', statusCode: 401);
    }
    return token;
  }

  static void _throwForPhotoResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    if (response.statusCode == 401) {
      ApiTransport.expireAccessToken();
      throw const ApiException('로그인이 필요하거나 로그인 시간이 만료되었습니다.', statusCode: 401);
    }
    if (response.statusCode == 413) {
      throw const ApiException('프로필 사진은 5MB 이하만 등록할 수 있습니다.', statusCode: 413);
    }
    if (response.statusCode == 422) {
      throw const ApiException(
        'JPEG, PNG, WebP 형식의 이미지 파일만 등록할 수 있습니다.',
        statusCode: 422,
      );
    }

    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic> && body['detail'] is String) {
        throw ApiException(
          body['detail'] as String,
          statusCode: response.statusCode,
        );
      }
    } on FormatException {
      // Keep a safe generic message for malformed error payloads.
    }
    throw ApiException(
      '프로필 사진 요청을 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.',
      statusCode: response.statusCode,
    );
  }

  static UserProfile _profileFromResponse(dynamic response) {
    if (response is! Map<String, dynamic>) {
      throw const ApiException('프로필 응답을 확인할 수 없습니다.');
    }
    try {
      return UserProfile.fromJson(response);
    } on FormatException {
      throw const ApiException('프로필 응답을 확인할 수 없습니다.');
    }
  }

  static Future<void> logout() async {
    try {
      await ApiTransport.post('/auth/logout');
    } on ApiException catch (error) {
      if (error.statusCode != 401) rethrow;
    } finally {
      ApiTransport.clearAccessToken();
    }
  }
}
