import '../../../shared/models/user.dart';

/// 기록 상세 화면에서만 사용하는 로컬 댓글 스레드 모델입니다.
class CommentItem {
  CommentItem({
    required this.id,
    required this.author,
    required this.createdAt,
    required this.content,
    List<CommentItem>? replies,
  }) : replies = replies ?? [];

  final String id;
  final User author;
  final DateTime createdAt;
  final String content;
  final List<CommentItem> replies;
}
