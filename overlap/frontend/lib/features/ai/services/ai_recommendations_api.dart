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
  static const supportedCategories = <String>{
    'all',
    'food',
    'bar',
    'cafe',
    'nature',
    'activity',
  };
  final RecommendationGet _get;
  final RecommendationGetWithStatus? _getWithStatus;
  String? _ownerToken;
  final Set<String> _loadedCategories = {};
  final Map<String, Future<List<AiPlaceRecommendation>>> _pending = {};

  Future<List<AiPlaceRecommendation>> load({String category = 'all'}) {
    if (!supportedCategories.contains(category)) {
      throw ArgumentError.value(
        category,
        'category',
        'Unsupported recommendation category',
      );
    }
    final token = ApiTransport.accessToken;
    if (_ownerToken != token) {
      _ownerToken = token;
      _loadedCategories.clear();
      _pending.clear();
    }
    final inFlight = _pending[category];
    if (inFlight != null) return inFlight;
    final refresh = _loadedCategories.contains(category);
    late final Future<List<AiPlaceRecommendation>> request;
    request = _load(category: category, refresh: refresh, ownerToken: token)
        .whenComplete(() {
          if (identical(_pending[category], request)) _pending.remove(category);
        });
    _pending[category] = request;
    return request;
  }

  Future<List<AiPlaceRecommendation>> _load({
    required String category,
    required bool refresh,
    required String? ownerToken,
  }) async {
    final stopwatch = Stopwatch()..start();
    final query = <String, String>{'category': category};
    if (refresh) query['refresh'] = 'true';
    final path = Uri(path: _endpoint, queryParameters: query).toString();
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
      final items =
          (body as Map<String, dynamic>)['recommendations'] as List<dynamic>? ??
          const [];
      final recommendations = items
          .whereType<Map<String, dynamic>>()
          .map(AiPlaceRecommendation.fromJson)
          .toList();
      if (_ownerToken == ownerToken && ApiTransport.accessToken == ownerToken) {
        _loadedCategories.add(category);
      }
      if (kDebugMode) {
        debugPrint(
          '[AI recommendations] category=$category refresh=$refresh http_status=$httpStatus recommendation_count=${recommendations.length} elapsed_ms=${stopwatch.elapsedMilliseconds}',
        );
      }
      return recommendations;
    } on ApiException catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[AI recommendations] category=$category refresh=$refresh http_status=${error.statusCode ?? 'unavailable'} error_kind=${error.kind.name} elapsed_ms=${stopwatch.elapsedMilliseconds}',
        );
      }
      rethrow;
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[AI recommendations] category=$category refresh=$refresh http_status=unavailable error_type=${error.runtimeType} elapsed_ms=${stopwatch.elapsedMilliseconds}',
        );
      }
      rethrow;
    }
  }
}
