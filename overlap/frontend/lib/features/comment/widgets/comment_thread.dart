import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../memory/widgets/record_author_avatar.dart';
import '../models/comment_item.dart';

class CommentThread extends StatelessWidget {
  const CommentThread({
    super.key,
    required this.comment,
    this.onReply,
    this.showGroupLabel = false,
  });

  final CommentItem comment;
  final VoidCallback? onReply;
  final bool showGroupLabel;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CommentContent(
              comment: comment,
              isReply: false,
              showGroupLabel: showGroupLabel,
            ),
            if (onReply != null)
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
                child: _CommentContent(
                  comment: reply,
                  isReply: true,
                  showGroupLabel: showGroupLabel,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CommentContent extends StatelessWidget {
  const _CommentContent({
    required this.comment,
    required this.isReply,
    required this.showGroupLabel,
  });

  final CommentItem comment;
  final bool isReply;
  final bool showGroupLabel;

  @override
  Widget build(BuildContext context) {
    final groupName = comment.groupName?.trim();
    final shouldShowGroupLabel =
        showGroupLabel && groupName != null && groupName.isNotEmpty;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RecordAuthorAvatar(
          radius: isReply ? 14 : 17,
          name: comment.author.name,
          profileImagePath: comment.author.profileImagePath,
          backgroundColor: isReply ? AppColors.paleMint : AppColors.softMint,
          initialFontSize: isReply ? 12 : 14,
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
              if (shouldShowGroupLabel) ...[
                const SizedBox(height: AppSpacing.xxs),
                _GroupLabel(name: groupName),
              ],
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

class _GroupLabel extends StatelessWidget {
  const _GroupLabel({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.paleMint,
      borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      child: Text(
        name,
        style: const TextStyle(
          color: AppColors.deepNavy,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );
}
