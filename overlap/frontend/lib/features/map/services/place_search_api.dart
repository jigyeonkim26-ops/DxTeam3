import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/network/api_client.dart';
import '../models/kakao_place_search_result.dart';

enum PlaceSearchErrorKind {
  unauthorized,
  notFound,
  server,
  network,
  invalidResponse,
}

class PlaceSearchException implements Exception {
  const PlaceSearchException(this.kind, this.message);

  final PlaceSearchErrorKind kind;
  final String message;

  @override
  String toString() => message;
}

class PlaceSearchApi {
  PlaceSearchApi({Future<http.Response> Function(String query)? request})
    : _request = request ?? ApiClient.searchPlaces;

  final Future<http.Response> Function(String query) _request;

  Future<List<KakaoPlaceSearchResult>> search(String query) async {
    try {
      final response = await _request(query);
      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw const FormatException('장소 검색 응답이 배열이 아닙니다.');
      }
      return decoded
          .map((item) {
            if (item is! Map<String, dynamic>) {
              throw const FormatException('장소 검색 항목 형식이 올바르지 않습니다.');
            }
            return KakaoPlaceSearchResult.fromJson(item);
          })
          .toList(growable: false);
    } on ApiException catch (error) {
      final kind = switch (error.statusCode) {
        401 => PlaceSearchErrorKind.unauthorized,
        404 => PlaceSearchErrorKind.notFound,
        int status when status >= 500 => PlaceSearchErrorKind.server,
        null => PlaceSearchErrorKind.network,
        _ => PlaceSearchErrorKind.server,
      };
      final message = switch (kind) {
        PlaceSearchErrorKind.unauthorized => '로그인이 필요합니다. 다시 로그인해 주세요.',
        PlaceSearchErrorKind.notFound => '장소 검색 API를 찾을 수 없습니다.',
        PlaceSearchErrorKind.server => '장소 검색 중 서버 오류가 발생했습니다.',
        PlaceSearchErrorKind.network => '네트워크에 연결할 수 없습니다. 연결 상태를 확인해 주세요.',
        PlaceSearchErrorKind.invalidResponse => '장소 검색 응답을 읽을 수 없습니다.',
      };
      throw PlaceSearchException(kind, message);
    } on FormatException {
      throw const PlaceSearchException(
        PlaceSearchErrorKind.invalidResponse,
        '장소 검색 응답 형식이 올바르지 않습니다.',
      );
    }
  }
}
