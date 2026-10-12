import '../../../core/network/api_transport.dart';
import '../../../shared/models/user.dart';
import '../models/comment_item.dart';

abstract final class RecordCommentsApi {
  static Future<List<CommentItem>> getComments(
    String recordId, {
    String? groupId,
    bool scopeAll = false,
  }) async {
    if (scopeAll && groupId != null) {
      throw ArgumentError('groupId and scopeAll cannot be used together.');
    }
    final groupValue = groupId == null ? null : int.tryParse(groupId);
    if (groupId != null && groupValue == null) {
      throw ArgumentError.value(groupId, 'groupId');
    }
    final params = <String, String>{
      if (groupValue != null) 'group_id': '$groupValue',
      if (scopeAll) 'scope': 'all',
    };
    final query = Uri(queryParameters: params).query;
    final response = await ApiTransport.get(
      '/records/$recordId/comments${query.isEmpty ? '' : '?$query'}',
    );
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
    String? groupId,
  }) async {
    final groupValue = groupId == null ? null : int.tryParse(groupId);
    if (groupId != null && groupValue == null) {
      throw ArgumentError.value(groupId, 'groupId');
    }
    final response = await ApiTransport.post(
      '/records/$recordId/comments',
      body: {
        'content': content,
        'parent_comment_id': parentCommentId == null
            ? null
            : int.tryParse(parentCommentId),
        'group_id': groupValue,
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
    final group = json['group'];
    final createdAt = json['created_at'];
    if (author is! Map<String, dynamic> ||
        author['id'] == null ||
        author['name'] is! String ||
        json['id'] == null ||
        json['content'] is! String ||
        createdAt is! String) {
      throw const ApiException('댓글 응답을 확인할 수 없습니다.');
    }
    if (group != null &&
        (group is! Map<String, dynamic> ||
            group['id'] == null ||
            group['name'] is! String)) {
      throw const ApiException('?볤? 紐⑥엫 ?묐떟???뺤씤?????놁뒿?덈떎.');
    }
    return CommentItem(
      id: '${json['id']}',
      author: User(id: '${author['id']}', name: author['name'] as String),
      createdAt: DateTime.parse(createdAt).toLocal(),
      content: json['content'] as String,
      groupId: json['group_id']?.toString(),
      groupIds: (json['group_ids'] as List? ?? const [])
          .map((groupId) => '$groupId')
          .toList(growable: false),
      groupName: group == null ? null : group['name'] as String,
      isGlobal: json['is_global'] == true,
      parentCommentId: json['parent_comment_id']?.toString(),
    );
  }
}
