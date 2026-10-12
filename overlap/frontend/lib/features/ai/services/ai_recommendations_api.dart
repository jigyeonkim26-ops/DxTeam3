import '../../../core/network/api_transport.dart';
import '../models/ai_place_recommendation.dart';

class AiRecommendationsApi {
  static const _responseTimeout = Duration(seconds: 75);

  Future<List<AiPlaceRecommendation>> load() async {
    final body = await ApiTransport.get(
      '/ai/recommendations',
      responseTimeout: _responseTimeout,
    );
    final items =
        (body as Map<String, dynamic>)['recommendations'] as List<dynamic>? ??
        const [];
    return items
        .whereType<Map<String, dynamic>>()
        .map(AiPlaceRecommendation.fromJson)
        .toList();
  }
}
