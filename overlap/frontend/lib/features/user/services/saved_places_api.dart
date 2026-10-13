import 'package:flutter/foundation.dart';

import '../../../core/network/api_transport.dart';
import '../models/saved_place.dart';

typedef SavedPlacesGet = Future<dynamic> Function(String path);
typedef SavedPlacesMutation = Future<dynamic> Function(String path);
typedef SavedKakaoMutation = Future<dynamic> Function(String path, Object body);

class SavedPlacesApi {
  SavedPlacesApi({
    SavedPlacesGet? get,
    SavedPlacesMutation? post,
    SavedPlacesMutation? delete,
    SavedKakaoMutation? postKakao,
  }) : _get = get ?? ApiTransport.get,
       _post = post ?? ((path) => ApiTransport.post(path)),
       _delete = delete ?? ApiTransport.delete,
       _postKakao = postKakao ?? ((path, body) => ApiTransport.post(path, body: body));

  final SavedPlacesGet _get;
  final SavedPlacesMutation _post;
  final SavedPlacesMutation _delete;
  final SavedKakaoMutation _postKakao;

  static final revision = ValueNotifier<int>(0);

  Future<SavedPlaceState> state(int placeId) async {
    final response = await _get('/places/$placeId/saved');
    return _parseState(response);
  }

  Future<SavedPlaceState> save(int placeId) async {
    final state = _parseState(await _post('/places/$placeId/saved'));
    revision.value++;
    return state;
  }

  Future<SavedPlaceState> unsave(int placeId) async {
    final state = _parseState(await _delete('/places/$placeId/saved'));
    revision.value++;
    return state;
  }

  Future<KakaoPlaceLookup> lookupKakao(String kakaoPlaceId) async {
    final response = await _get('/places/kakao/${Uri.encodeComponent(kakaoPlaceId)}');
    if (response is! Map) {
      throw const ApiException('카카오 장소 응답을 확인할 수 없습니다.');
    }
    try {
      return KakaoPlaceLookup.fromJson(Map<String, dynamic>.from(response));
    } on FormatException {
      throw const ApiException('카카오 장소 응답을 확인할 수 없습니다.');
    }
  }

  Future<SavedPlaceState> saveKakao(String kakaoPlaceId, {required String name, required String address}) async {
    final response = await _postKakao(
      '/places/kakao/${Uri.encodeComponent(kakaoPlaceId)}/saved',
      {'name': name, 'address': address},
    );
    final state = _parseState(response);
    revision.value++;
    return state;
  }

  Future<List<SavedPlace>> list() async {
    final places = <SavedPlace>[];
    var offset = 0;
    while (true) {
      final response = await _get('/places/saved?offset=$offset&limit=100');
      if (response is! Map ||
          response['items'] is! List ||
          response['total'] is! int) {
        throw const ApiException('저장 장소 응답을 확인할 수 없습니다.');
      }
      final items = (response['items'] as List)
          .map((item) {
            if (item is! Map) {
              throw const ApiException('저장 장소 응답을 확인할 수 없습니다.');
            }
            try {
              return SavedPlace.fromJson(Map<String, dynamic>.from(item));
            } on FormatException {
              throw const ApiException('저장 장소 응답을 확인할 수 없습니다.');
            }
          })
          .toList(growable: false);
      places.addAll(items);
      offset += items.length;
      if (items.isEmpty || offset >= (response['total'] as int)) {
        return places;
      }
    }
  }

  SavedPlaceState _parseState(dynamic response) {
    if (response is! Map) {
      throw const ApiException('저장 상태 응답을 확인할 수 없습니다.');
    }
    try {
      return SavedPlaceState.fromJson(Map<String, dynamic>.from(response));
    } on FormatException {
      throw const ApiException('저장 상태 응답을 확인할 수 없습니다.');
    }
  }
}
