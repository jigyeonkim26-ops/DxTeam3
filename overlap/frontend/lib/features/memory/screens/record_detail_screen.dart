import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/record.dart';
import '../../../shared/models/user.dart';
import '../../comment/models/comment_item.dart';
import '../../comment/widgets/comment_input.dart';
import '../../comment/widgets/comment_thread.dart';

class RecordDetailScreen extends StatefulWidget {
  const RecordDetailScreen({super.key, required this.record});

  final Record record;

  @override
  State<RecordDetailScreen> createState() => _RecordDetailScreenState();
}

class _RecordDetailScreenState extends State<RecordDetailScreen> {
  final _commentController = TextEditingController();
  final _commentFocusNode = FocusNode();
  late int _likeCount;
  late List<CommentItem> _comments;
  bool _isLiked = false;
  CommentItem? _replyTarget;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.record.likeCount;
    _comments = _initialComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  List<CommentItem> _initialComments() {
    const seoyeon = User(id: 'comment-seoyeon', name: '서연');
    const doyoon = User(id: 'comment-doyoon', name: '도윤');
    const minji = User(id: 'comment-minji', name: '민지');
    return [
      CommentItem(
        id: 'comment-1',
        author: seoyeon,
        createdAt: DateTime(2026, 10, 2, 15, 24),
        content: '비 온 뒤 분위기가 정말 좋았겠다. 다음엔 같이 가자!',
        replies: [
          CommentItem(
            id: 'reply-1',
            author: widget.record.author,
            createdAt: DateTime(2026, 10, 2, 15, 28),
            content: '좋아, 맑은 날에도 꼭 다시 가자!',
          ),
        ],
      ),
      CommentItem(
        id: 'comment-2',
        author: doyoon,
        createdAt: DateTime(2026, 10, 2, 15, 32),
        content: '사진 색감이 너무 좋아. 나도 이곳 저장해둘게.',
      ),
      CommentItem(
        id: 'comment-3',
        author: minji,
        createdAt: DateTime(2026, 10, 2, 15, 41),
        content: '다음 산책은 여기서 시작해도 좋겠다.',
      ),
    ];
  }

  int get _commentCount => _comments.fold<int>(
    0,
    (count, comment) => count + 1 + comment.replies.length,
  );

  void _toggleLike() {
    setState(() {
      _isLiked = !_isLiked;
      _likeCount += _isLiked ? 1 : -1;
    });
  }

  void _submitComment() {
    final content = _commentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('댓글 내용을 입력해 주세요.')));
      return;
    }

    const currentUser = User(id: 'current-user', name: '서연');
    final item = CommentItem(
      id: 'comment-${DateTime.now().microsecondsSinceEpoch}',
      author: currentUser,
      createdAt: DateTime.now(),
      content: content,
    );
    setState(() {
      if (_replyTarget == null) {
        _comments.add(item);
      } else {
        _replyTarget!.replies.add(item);
      }
      _replyTarget = null;
      _commentController.clear();
    });
    FocusScope.of(context).unfocus();
  }

  void _selectReply(CommentItem comment) {
    setState(() => _replyTarget = comment);
    _commentFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    return Scaffold(
      backgroundColor: AppColors.paper,
      resizeToAvoidBottomInset: true,
      bottomNavigationBar: CommentInput(
        controller: _commentController,
        focusNode: _commentFocusNode,
        onSubmit: _submitComment,
        replyingToName: _replyTarget?.author.name,
        onCancelReply: () => setState(() => _replyTarget = null),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.lg,
          ),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back),
                  tooltip: '뒤로가기',
                ),
                const SizedBox(width: AppSpacing.xxs),
                const Expanded(
                  child: Text(
                    '기록 상세',
                    style: TextStyle(
                      color: AppColors.deepNavy,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _RecordAuthor(
                      record: record,
                      onPlaceTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('장소 상세는 추후 연결됩니다.')),
                        );
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _RecordPhoto(record: record),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      record.content,
                      style: const TextStyle(
                        color: AppColors.deepNavy,
                        fontSize: 16,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        _DetailChip(
                          label:
                              '${record.emotion.emoji} ${record.emotion.displayName}',
                        ),
                        for (final group in record.sharedGroups)
                          _DetailChip(label: group.name),
                      ],
                    ),
                    const Divider(height: AppSpacing.lg),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _toggleLike,
                          icon: Icon(
                            _isLiked ? Icons.favorite : Icons.favorite_border,
                            color: _isLiked
                                ? AppColors.coral
                                : AppColors.deepNavy,
                          ),
                          label: Text('공감 $_likeCount'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.deepNavy,
                            side: BorderSide(
                              color: _isLiked
                                  ? AppColors.coral
                                  : AppColors.muted,
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          '댓글 $_commentCount',
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '댓글 $_commentCount',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.deepNavy,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            for (final comment in _comments) ...[
              CommentThread(
                comment: comment,
                onReply: () => _selectReply(comment),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecordAuthor extends StatelessWidget {
  const _RecordAuthor({required this.record, required this.onPlaceTap});

  final Record record;
  final VoidCallback onPlaceTap;

  @override
  Widget build(BuildContext context) {
    final minute = record.createdAt.minute.toString().padLeft(2, '0');
    return Row(
      children: [
        CircleAvatar(
          radius: 21,
          backgroundColor: AppColors.softMint,
          foregroundColor: AppColors.deepNavy,
          child: Text(
            record.author.name.substring(0, 1),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                record.author.name,
                style: const TextStyle(
                  color: AppColors.deepNavy,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '오늘 ${record.createdAt.hour}:$minute',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: AppSpacing.xxs),
              InkWell(
                onTap: onPlaceTap,
                borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        color: AppColors.muted,
                        size: 14,
                      ),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          record.place.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Text(record.emotion.emoji, style: const TextStyle(fontSize: 28)),
      ],
    );
  }
}

class _RecordPhoto extends StatelessWidget {
  const _RecordPhoto({required this.record});

  final Record record;

  @override
  Widget build(BuildContext context) {
    final colors = switch (record.id) {
      'place-record-sun' => const [Color(0xFFE9B67A), Color(0xFFFF7058)],
      'place-record-rain' => const [Color(0xFF86A7B6), AppColors.deepNavy],
      _ when record.id.contains('coast') => const [
        Color(0xFF5E8EA8),
        Color(0xFFFFB26B),
      ],
      _ when record.id.contains('park') => const [
        Color(0xFF86B88C),
        Color(0xFFDCEFE5),
      ],
      _ when record.id.contains('bakery') => const [
        Color(0xFFE6B07A),
        Color(0xFF9B6A57),
      ],
      _ => const [Color(0xFF9FC4B2), Color(0xFF5C8474)],
    };
    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      ),
      child: const Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: Icon(Icons.image_outlined, color: Colors.white70, size: 28),
        ),
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.paleMint,
        borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
      ),
      child: Text(
        label,
        style: const TextStyle(color: AppColors.deepNavy, fontSize: 12),
      ),
    );
  }
}
