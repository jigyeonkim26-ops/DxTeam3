import 'package:flutter/foundation.dart';

import '../../../core/network/api_transport.dart';
import '../models/ai_place_recommendation.dart';

typedef RecommendationGet = Future<dynamic> Function(
  String path, {
  Duration? responseTimeout,
});
typedef RecommendationGetWithStatus = Future<dynamic> Function(
  String path, {
  Duration? responseTimeout,
  required void Function(int statusCode) onResponse,
});

class AiRecommendationsApi {
  AiRecommendationsApi({
    RecommendationGet? get,
    RecommendationGetWithStatus? getWithStatus,
  }) : _get = get ?? ApiTransport.get,
       _getWithStatus =
           getWithStatus ?? (get == null ? ApiTransport.getWithStatus : null);

  // Sequential provider calls can take up to 156 seconds at their own limits.
  static const _responseTimeout = Duration(seconds: 180);
  static const _endpoint = '/ai/recommendations';
  final RecommendationGet _get;
  final RecommendationGetWithStatus? _getWithStatus;
  String? _ownerToken;
  bool _loaded = false;
  Future<List<AiPlaceRecommendation>>? _pending;
  String sessionStatus = 'available';

  Future<List<AiPlaceRecommendation>> load() {
    final token = ApiTransport.accessToken;
    if (_ownerToken != token) {
      _ownerToken = token;
      _loaded = false;
      _pending = null;
      sessionStatus = 'available';
    }
    final inFlight = _pending;
    if (inFlight != null) return inFlight;
    final refresh = _loaded;
    late final Future<List<AiPlaceRecommendation>> request;
    request = _load(refresh: refresh, ownerToken: token).whenComplete(() {
      if (identical(_pending, request)) _pending = null;
    });
    _pending = request;
    return request;
  }

  Future<List<AiPlaceRecommendation>> _load({
    required bool refresh,
    required String? ownerToken,
  }) async {
    final stopwatch = Stopwatch()..start();
    final query = <String, String>{};
    if (refresh) query['refresh'] = 'true';
    final path = query.isEmpty
        ? _endpoint
        : Uri(path: _endpoint, queryParameters: query).toString();
    var httpStatus = 'unknown';
    try {
      final statusAwareGet = _getWithStatus;
      final body = statusAwareGet == null
          ? await _get(path, responseTimeout: _responseTimeout)
          : await statusAwareGet(
              path,
              responseTimeout: _responseTimeout,
              onResponse: (statusCode) => httpStatus = '$statusCode',
            );
      final responseBody = body as Map<String, dynamic>;
      final items =
          responseBody['recommendations'] as List<dynamic>? ?? const [];
      final rawStatus = responseBody['session_status'];
      if (_ownerToken == ownerToken &&
          ApiTransport.accessToken == ownerToken) {
        sessionStatus = rawStatus is String &&
                const {'available', 'exhausted', 'empty'}.contains(rawStatus)
            ? rawStatus
            : 'available';
      }
      final recommendations = items
          .whereType<Map<String, dynamic>>()
          .map(AiPlaceRecommendation.fromJson)
          .toList();
      if (_ownerToken == ownerToken && ApiTransport.accessToken == ownerToken) {
        _loaded = true;
      }
      if (kDebugMode) {
        debugPrint(
          '[AI recommendations] refresh=$refresh http_status=$httpStatus recommendation_count=${recommendations.length} elapsed_ms=${stopwatch.elapsedMilliseconds}',
        );
      }
      return recommendations;
    } on ApiException catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[AI recommendations] refresh=$refresh http_status=${error.statusCode ?? 'unavailable'} error_kind=${error.kind.name} elapsed_ms=${stopwatch.elapsedMilliseconds}',
        );
      }
      rethrow;
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[AI recommendations] refresh=$refresh http_status=unavailable error_type=${error.runtimeType} elapsed_ms=${stopwatch.elapsedMilliseconds}',
        );
      }
      rethrow;
    }
  }
}
