import '../../../core/network/api_transport.dart';
import '../models/ai_place_recommendation.dart';

typedef RecommendationGet = Future<dynamic> Function(
  String path, {
  Duration? responseTimeout,
});

class AiRecommendationsApi {
  AiRecommendationsApi({RecommendationGet? get})
    : _get = get ?? ApiTransport.get;

  // Sequential provider calls can take up to 156 seconds at their own limits.
  static const _responseTimeout = Duration(seconds: 180);
  static const _endpoint = '/ai/recommendations';
  final RecommendationGet _get;
  final Set<String> _seenPlaceIds = {};
  final Set<String> _previousPlaceIds = {};
  String? _ownerToken;

  Future<List<AiPlaceRecommendation>> load() async {
    final token = ApiTransport.accessToken;
    if (_ownerToken != token) {
      _seenPlaceIds.clear();
      _previousPlaceIds.clear();
      _ownerToken = token;
    }
    final query = _seenPlaceIds.isEmpty
        ? null
        : {
            'exclude_place_ids': _seenPlaceIds.take(60).join(','),
            if (_previousPlaceIds.isNotEmpty)
              'previous_place_ids': _previousPlaceIds.join(','),
          };
    final path = query == null
        ? _endpoint
        : Uri(path: _endpoint, queryParameters: query).toString();
    final body = await _get(path, responseTimeout: _responseTimeout);
    final items =
        (body as Map<String, dynamic>)['recommendations'] as List<dynamic>? ??
        const [];
    final recommendations = items
        .whereType<Map<String, dynamic>>()
        .map(AiPlaceRecommendation.fromJson)
        .toList();
    _previousPlaceIds
      ..clear()
      ..addAll(
        recommendations
            .map((item) => item.kakaoPlaceId)
            .whereType<String>()
            .where((id) => id.isNotEmpty),
      );
    for (final item in recommendations) {
      final id = item.kakaoPlaceId;
      if (id != null && id.isNotEmpty) _seenPlaceIds.add(id);
    }
    return recommendations;
  }
}
