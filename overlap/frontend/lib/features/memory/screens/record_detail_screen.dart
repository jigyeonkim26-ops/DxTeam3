import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/record.dart';
import '../widgets/record_photo.dart';
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
  final bool _isLiked = false;
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

  List<CommentItem> _initialComments() => [];

  int get _commentCount => _comments.fold<int>(
    0,
    (count, comment) => count + 1 + comment.replies.length,
  );

  void _toggleLike() {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('공감 기능은 준비 중입니다.')));
  }

  void _submitComment() {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('댓글 기능은 준비 중입니다.')));
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
                    RecordPhoto(paths: record.imagePaths, height: 240),
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
