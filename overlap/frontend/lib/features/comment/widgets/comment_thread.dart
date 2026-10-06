import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../models/comment_item.dart';

class CommentThread extends StatelessWidget {
  const CommentThread({
    super.key,
    required this.comment,
    required this.onReply,
  });

  final CommentItem comment;
  final VoidCallback onReply;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CommentContent(comment: comment, isReply: false),
            TextButton.icon(
              onPressed: onReply,
              icon: const Icon(Icons.reply_outlined, size: 17),
              label: const Text('답글'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.deepNavy,
                padding: const EdgeInsets.only(top: AppSpacing.xs),
              ),
            ),
            for (final reply in comment.replies) ...[
              const Divider(height: AppSpacing.md),
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.md),
                child: _CommentContent(comment: reply, isReply: true),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CommentContent extends StatelessWidget {
  const _CommentContent({required this.comment, required this.isReply});

  final CommentItem comment;
  final bool isReply;

  @override
  Widget build(BuildContext context) {
    final initial = comment.author.name.isEmpty
        ? '?'
        : comment.author.name.substring(0, 1);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: isReply ? 14 : 17,
          backgroundColor: isReply ? AppColors.paleMint : AppColors.softMint,
          foregroundColor: AppColors.deepNavy,
          child: Text(
            initial,
            style: TextStyle(
              fontSize: isReply ? 12 : 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    comment.author.name,
                    style: const TextStyle(
                      color: AppColors.deepNavy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      _formattedTime(comment.createdAt),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                comment.content,
                style: const TextStyle(color: AppColors.deepNavy, height: 1.45),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formattedTime(DateTime time) {
    final minute = time.minute.toString().padLeft(2, '0');
    return '오늘 ${time.hour}:$minute';
  }
}
