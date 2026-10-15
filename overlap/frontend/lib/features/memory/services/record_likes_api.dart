import '../../../core/network/async_request_gate.dart';
import '../../../core/network/api_transport.dart';

class RecordLikeState {
  const RecordLikeState({required this.likeCount, required this.liked});

  final int likeCount;
  final bool liked;

  factory RecordLikeState.fromJson(dynamic json) {
    if (json is! Map<String, dynamic> ||
        json['like_count'] is! int ||
        json['liked'] is! bool) {
      throw const ApiException('공감 응답을 확인할 수 없습니다.');
    }
    return RecordLikeState(
      likeCount: json['like_count'] as int,
      liked: json['liked'] as bool,
    );
  }
}

/// Uses the authenticated record likes endpoints without maintaining local
/// optimistic state. The server response is always the displayed source.
abstract final class RecordLikesApi {
  static const int maxConcurrentStateReads = 6;
  static final AsyncRequestGate _stateReadGate = AsyncRequestGate(
    maxConcurrentStateReads,
  );

  static Future<RecordLikeState> getState(String recordId) =>
      _stateReadGate.run(() async {
        return RecordLikeState.fromJson(
          await ApiTransport.get('/records/$recordId/likes'),
        );
      });

  static Future<RecordLikeState> like(String recordId) async =>
      RecordLikeState.fromJson(
        await ApiTransport.post('/records/$recordId/likes'),
      );

  static Future<RecordLikeState> unlike(String recordId) async =>
      RecordLikeState.fromJson(
        await ApiTransport.delete('/records/$recordId/likes'),
      );
}
