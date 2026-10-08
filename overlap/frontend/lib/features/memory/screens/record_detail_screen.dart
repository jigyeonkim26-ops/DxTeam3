import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/record.dart';
import '../widgets/record_photo.dart';
import '../services/record_api.dart';
import '../services/record_likes_api.dart';
import '../../comment/models/comment_item.dart';
import '../../comment/services/record_comments_api.dart';
import '../../comment/widgets/comment_input.dart';
import '../../comment/widgets/comment_thread.dart';
import 'record_edit_screen.dart';

class RecordDetailResult {
  const RecordDetailResult.updated(Record record)
    : updatedRecord = record,
      deletedRecordId = null;

  const RecordDetailResult.deleted(String recordId)
    : updatedRecord = null,
      deletedRecordId = recordId;

  final Record? updatedRecord;
  final String? deletedRecordId;
}

enum _RecordMenuAction { edit, delete }

class RecordDetailScreen extends StatefulWidget {
  const RecordDetailScreen({
    super.key,
    required this.record,
    this.recordApi,
    this.canManage = false,
  });

  final Record record;
  final RecordApi? recordApi;
  final bool canManage;

  @override
  State<RecordDetailScreen> createState() => _RecordDetailScreenState();
}

class _RecordDetailScreenState extends State<RecordDetailScreen> {
  final _commentController = TextEditingController();
  final _commentFocusNode = FocusNode();
  late int _likeCount;
  late List<CommentItem> _comments;
  var _isLiked = false;
  var _isLikeLoading = false;
  var _isCommentsLoading = false;
  var _isSubmittingComment = false;
  String? _commentsError;
  CommentItem? _replyTarget;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _likeCount = widget.record.likeCount;
    _comments = [];
    _loadLikeState();
    _loadComments();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocusNode.dispose();
    super.dispose();
  }

  int get _commentCount => _comments.fold<int>(
    0,
    (count, comment) => count + 1 + comment.replies.length,
  );

  Future<void> _loadLikeState() async {
    try {
      final state = await RecordLikesApi.getState(widget.record.id);
      if (mounted) {
        setState(() {
          _isLiked = state.liked;
          _likeCount = state.likeCount;
        });
      }
    } on ApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  Future<void> _toggleLike() async {
    if (_isLikeLoading) return;
    setState(() => _isLikeLoading = true);
    try {
      final state = _isLiked
          ? await RecordLikesApi.unlike(widget.record.id)
          : await RecordLikesApi.like(widget.record.id);
      if (mounted) {
        setState(() {
          _isLiked = state.liked;
          _likeCount = state.likeCount;
        });
      }
    } on ApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _isLikeLoading = false);
    }
  }

  Future<void> _loadComments() async {
    if (mounted) {
      setState(() {
        _isCommentsLoading = true;
        _commentsError = null;
      });
    }
    try {
      final items = await RecordCommentsApi.getComments(widget.record.id);
      final byId = {for (final item in items) item.id: item};
      final roots = <CommentItem>[];
      for (final item in items) {
        final parentId = item.parentCommentId;
        final parent = parentId == null ? null : byId[parentId];
        if (parent == null) {
          roots.add(item);
        } else {
          parent.replies.add(item);
        }
      }
      if (mounted) setState(() => _comments = roots);
    } on ApiException catch (error) {
      if (mounted) setState(() => _commentsError = error.message);
    } finally {
      if (mounted) setState(() => _isCommentsLoading = false);
    }
  }

  Future<void> _submitComment() async {
    if (_isSubmittingComment) return;
    final content = _commentController.text.trim();
    if (content.isEmpty) return;

    setState(() => _isSubmittingComment = true);
    try {
      await RecordCommentsApi.createComment(
        widget.record.id,
        content,
        parentCommentId: _replyTarget?.id,
      );
      if (!mounted) return;
      _commentController.clear();
      setState(() => _replyTarget = null);
      await _loadComments();
    } on ApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _isSubmittingComment = false);
    }
  }

  void _selectReply(CommentItem comment) {
    setState(() => _replyTarget = comment);
    _commentFocusNode.requestFocus();
  }

  bool get _canManage => widget.canManage && widget.recordApi != null;

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _onMenuSelected(_RecordMenuAction action) async {
    if (_isDeleting || !_canManage) return;
    if (action == _RecordMenuAction.edit) {
      final updated = await Navigator.of(context).push<Record>(
        MaterialPageRoute<Record>(
          builder: (_) => RecordEditScreen(
            record: widget.record,
            recordApi: widget.recordApi!,
          ),
        ),
      );
      if (!mounted || updated == null) return;
      Navigator.of(context).pop(RecordDetailResult.updated(updated));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('기록을 삭제할까요?'),
        content: const Text('삭제한 기록과 연결된 사진은 복구할 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.coral),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);
    try {
      await widget.recordApi!.delete(widget.record.id);
      if (!mounted) return;
      Navigator.of(context).pop(RecordDetailResult.deleted(widget.record.id));
    } on ApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('기록을 삭제하지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
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
        isSubmitting: _isSubmittingComment,
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
                if (_canManage)
                  _isDeleting
                      ? const Padding(
                          padding: EdgeInsets.all(AppSpacing.sm),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : PopupMenuButton<_RecordMenuAction>(
                          tooltip: '기록 메뉴',
                          onSelected: _onMenuSelected,
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: _RecordMenuAction.edit,
                              child: Text('수정'),
                            ),
                            PopupMenuItem(
                              value: _RecordMenuAction.delete,
                              child: Text('삭제'),
                            ),
                          ],
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
                          onPressed: _isLikeLoading ? null : _toggleLike,
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
            if (_isCommentsLoading)
              const Center(child: CircularProgressIndicator())
            else if (_commentsError != null)
              _CommentsError(
                message: _commentsError!,
                onRetry: _loadComments,
              )
            else if (_comments.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                child: Center(
                  child: Text(
                    '아직 댓글이 없어요.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                ),
              )
            else
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

class _CommentsError extends StatelessWidget {
  const _CommentsError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
    child: Column(
      children: [
        Text(message, style: const TextStyle(color: AppColors.muted)),
        TextButton(onPressed: onRetry, child: const Text('다시 시도')),
      ],
    ),
  );
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
