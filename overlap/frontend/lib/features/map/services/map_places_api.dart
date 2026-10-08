import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/network/api_client.dart';
import '../../../core/network/api_config.dart';
import '../models/map_place.dart';

enum MapPlacesApiErrorKind { unauthorized, server, network, invalidResponse }

class MapPlacesApiException implements Exception {
  const MapPlacesApiException(this.kind);

  final MapPlacesApiErrorKind kind;
}

/// Loads record-count map pins visible to the currently authenticated user.
class MapPlacesApi {
  MapPlacesApi({Future<http.Response> Function()? request})
    : _request = request ?? _requestMapPlaces;

  final Future<http.Response> Function() _request;

  static Future<http.Response> _requestMapPlaces() async {
    final token = ApiClient.accessToken;
    if (token == null || token.isEmpty) {
      throw const ApiException('로그인이 필요합니다.', statusCode: 401);
    }

    try {
      return await http
          .get(
            Uri.parse('${ApiConfig.baseUrl}/map/places'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 15));
    } on ApiException {
      rethrow;
    } catch (_) {
      throw const MapPlacesApiException(MapPlacesApiErrorKind.network);
    }
  }

  Future<List<MapPlace>> load() async {
    try {
      final response = await _request();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw MapPlacesApiException(
          response.statusCode == 401
              ? MapPlacesApiErrorKind.unauthorized
              : MapPlacesApiErrorKind.server,
        );
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! List) {
        throw const MapPlacesApiException(
          MapPlacesApiErrorKind.invalidResponse,
        );
      }

      final placesById = <String, MapPlace>{};
      for (final item in decoded) {
        if (item is! Map) continue;
        final place = MapPlace.tryFromMapPlacesApiJson(
          Map<String, dynamic>.from(item),
        );
        if (place != null) placesById.putIfAbsent(place.id, () => place);
      }
      return placesById.values.toList(growable: false);
    } on MapPlacesApiException {
      rethrow;
    } on ApiException catch (error) {
      throw MapPlacesApiException(
        error.statusCode == 401
            ? MapPlacesApiErrorKind.unauthorized
            : MapPlacesApiErrorKind.server,
      );
    } on FormatException {
      throw const MapPlacesApiException(MapPlacesApiErrorKind.invalidResponse);
    } catch (_) {
      throw const MapPlacesApiException(MapPlacesApiErrorKind.network);
    }
  }
}
