import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_config.dart';
import '../../../shared/models/emotion.dart';
import '../../../shared/models/group.dart';
import '../../../shared/models/place.dart';
import '../../../shared/models/record.dart';

class RecordApi {
  RecordApi({http.Client? client, String? Function()? tokenProvider})
    : _client = client ?? http.Client(),
      _tokenProvider = tokenProvider ?? (() => ApiClient.accessToken);

  final http.Client _client;
  final String? Function() _tokenProvider;
  static final revision = ValueNotifier<int>(0);

  Map<String, String> get _headers {
    final token = _tokenProvider();
    if (token == null || token.isEmpty) {
      throw const ApiException('로그인이 필요합니다.', statusCode: 401);
    }
    return {'Authorization': 'Bearer $token'};
  }

  dynamic _decode(http.Response response) {
    final isSuccess = response.statusCode >= 200 && response.statusCode < 300;
    if (!isSuccess && response.statusCode == 401) {
      ApiClient.expireSession();
    }
    final payload = response.bodyBytes.isEmpty
        ? null
        : jsonDecode(utf8.decode(response.bodyBytes));
    if (!isSuccess) {
      final detail = payload is Map ? payload['detail'] : null;
      throw ApiException(
        detail is String ? detail : '요청을 처리하지 못했습니다. 다시 시도해 주세요.',
        statusCode: response.statusCode,
      );
    }
    return payload;
  }

  Future<dynamic> _get(String path) async {
    try {
      return _decode(
        await _client
            .get(Uri.parse('${ApiConfig.baseUrl}$path'), headers: _headers)
            .timeout(const Duration(seconds: 15)),
      );
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException('기록을 불러오지 못했습니다. 연결 상태를 확인해 주세요.');
    }
  }

  Future<List<Group>> groups() async => (await _get('/records/groups') as List)
      .map(
        (item) => Group(
          id: '${item['id']}',
          name: item['name'] as String,
          description: item['description'] as String? ?? '',
          memberCount: item['member_count'] as int? ?? 0,
        ),
      )
      .toList();

  Future<List<Record>> feed({bool mine = false, String? groupId}) async {
    final params = {
      'limit': '100',
      if (mine) 'mine': 'true',
      'group_id': ?groupId,
    };
    final query = Uri(queryParameters: params).query;
    final items = <Record>[];
    var offset = 0;
    while (true) {
      final page = await _get('/feed?$query&offset=$offset') as Map;
      final batch = (page['items'] as List)
          .map(
            (item) => Record.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList();
      items.addAll(batch);
      offset += batch.length;
      if (batch.isEmpty || offset >= (page['total'] as int)) return items;
    }
  }

  Future<Record> create({
    required List<XFile> photos,
    required Emotion emotion,
    required Place place,
    required String content,
    required bool isPrivate,
    required Set<String> groupIds,
  }) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('${ApiConfig.baseUrl}/records'))
          ..headers.addAll(_headers)
          ..fields['data'] = jsonEncode({
            'place': {
              'kakao_place_id': place.id,
              'name': place.name,
              'address': place.address ?? '',
              'latitude': place.latitude,
              'longitude': place.longitude,
            },
            'emotion': emotion.name,
            'content': content.trim(),
            'is_private': isPrivate,
            'group_ids': isPrivate ? <int>[] : groupIds.map(int.parse).toList(),
          });
    try {
      for (final photo in photos) {
        request.files.add(
          http.MultipartFile.fromBytes(
            'photos',
            await photo.readAsBytes(),
            filename: photo.name,
          ),
        );
      }
      final response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 60)),
      ).timeout(const Duration(seconds: 60));
      final record = Record.fromJson(
        Map<String, dynamic>.from(_decode(response) as Map),
      );
      revision.value++;
      return record;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException('기록을 저장하지 못했습니다. 연결 상태를 확인하고 다시 시도해 주세요.');
    }
  }

  Future<Record> update({
    required String recordId,
    required String content,
    required Emotion emotion,
    required bool isPrivate,
    required Set<String> groupIds,
  }) async {
    try {
      final response = await _client
          .patch(
            Uri.parse('${ApiConfig.baseUrl}/records/$recordId'),
            headers: {..._headers, 'Content-Type': 'application/json'},
            body: jsonEncode({
              'content': content.trim(),
              'emotion': emotion.name,
              'is_private': isPrivate,
              'group_ids': isPrivate
                  ? <int>[]
                  : groupIds.map(int.parse).toList(),
            }),
          )
          .timeout(const Duration(seconds: 30));
      final record = Record.fromJson(
        Map<String, dynamic>.from(_decode(response) as Map),
      );
      revision.value++;
      return record;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException('기록을 수정하지 못했습니다. 연결 상태를 확인하고 다시 시도해 주세요.');
    }
  }

  Future<void> delete(String recordId) async {
    try {
      final response = await _client
          .delete(
            Uri.parse('${ApiConfig.baseUrl}/records/$recordId'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 30));
      _decode(response);
      revision.value++;
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const ApiException('기록을 삭제하지 못했습니다. 연결 상태를 확인하고 다시 시도해 주세요.');
    }
  }

  void close() => _client.close();
}
