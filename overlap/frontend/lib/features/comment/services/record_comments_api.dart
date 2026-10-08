import '../../../core/network/api_transport.dart';
import '../../../shared/models/user.dart';
import '../models/comment_item.dart';

abstract final class RecordCommentsApi {
  static Future<List<CommentItem>> getComments(String recordId) async {
    final response = await ApiTransport.get('/records/$recordId/comments');
    if (response is! Map<String, dynamic> || response['items'] is! List) {
      throw const ApiException('댓글 목록 응답을 확인할 수 없습니다.');
    }
    return (response['items'] as List)
        .whereType<Map<String, dynamic>>()
        .map(_commentFromJson)
        .toList(growable: false);
  }

  static Future<CommentItem> createComment(
    String recordId,
    String content, {
    String? parentCommentId,
  }) async {
    final response = await ApiTransport.post(
      '/records/$recordId/comments',
      body: {
        'content': content,
        'parent_comment_id': parentCommentId == null
            ? null
            : int.tryParse(parentCommentId),
      },
    );
    if (response is! Map<String, dynamic>) {
      throw const ApiException('댓글 작성 응답을 확인할 수 없습니다.');
    }
    return _commentFromJson(response);
  }

  static Future<void> deleteComment(String recordId, String commentId) async {
    await ApiTransport.delete('/records/$recordId/comments/$commentId');
  }

  static CommentItem _commentFromJson(Map<String, dynamic> json) {
    final author = json['author'];
    final createdAt = json['created_at'];
    if (author is! Map<String, dynamic> ||
        author['id'] == null ||
        author['name'] is! String ||
        json['id'] == null ||
        json['content'] is! String ||
        createdAt is! String) {
      throw const ApiException('댓글 응답을 확인할 수 없습니다.');
    }
    return CommentItem(
      id: '${json['id']}',
      author: User(id: '${author['id']}', name: author['name'] as String),
      createdAt: DateTime.parse(createdAt).toLocal(),
      content: json['content'] as String,
      parentCommentId: json['parent_comment_id']?.toString(),
    );
  }
}
