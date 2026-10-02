import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/record.dart';

class RecordCard extends StatelessWidget {
  const RecordCard({
    super.key,
    required this.record,
    required this.isLiked,
    required this.onLikeTap,
    required this.onCommentTap,
    required this.onPlaceTap,
  });

  final Record record;
  final bool isLiked;
  final VoidCallback onLikeTap;
  final VoidCallback onCommentTap;
  final VoidCallback onPlaceTap;

  @override
  Widget build(BuildContext context) {
    final likeCount = record.likeCount + (isLiked ? 1 : 0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Avatar(name: record.author.name),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.author.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        _formattedTime(record.createdAt),
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  record.emotion.emoji,
                  style: const TextStyle(fontSize: 22),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: onPlaceTap,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.deepNavy,
                padding: EdgeInsets.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.location_on_outlined, size: 17),
              label: Text(
                record.place.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(record.content, style: const TextStyle(height: 1.5)),
            const SizedBox(height: AppSpacing.sm),
            _PhotoPlaceholder(record: record),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                _EmotionChip(record: record),
                for (final group in record.sharedGroups)
                  _GroupChip(label: group.name),
              ],
            ),
            const Divider(height: AppSpacing.lg),
            Row(
              children: [
                _ActionButton(
                  icon: isLiked ? Icons.favorite : Icons.favorite_border,
                  label: '공감 $likeCount',
                  color: isLiked ? AppColors.coral : AppColors.muted,
                  onTap: onLikeTap,
                ),
                const SizedBox(width: AppSpacing.lg),
                _ActionButton(
                  icon: Icons.chat_bubble_outline,
                  label: '댓글 ${record.commentCount}',
                  color: AppColors.muted,
                  onTap: onCommentTap,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formattedTime(DateTime time) {
    final now = DateTime.now();
    final isToday =
        now.year == time.year && now.month == time.month && now.day == time.day;
    final minute = time.minute.toString().padLeft(2, '0');
    return isToday ? '오늘 ${time.hour}:$minute' : '${time.month}월 ${time.day}일';
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 20,
      backgroundColor: AppColors.softMint,
      foregroundColor: AppColors.deepNavy,
      child: Text(
        name.substring(0, 1),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({required this.record});

  final Record record;

  @override
  Widget build(BuildContext context) {
    final colors = switch (record.emotion) {
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
      _ => const [Color(0xFF9FC4B2), AppColors.deepNavy],
    };
    return Container(
      height: 176,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Align(
        alignment: Alignment.bottomLeft,
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.sm),
          child: Icon(Icons.image_outlined, color: Colors.white70),
        ),
      ),
    );
  }
}

class _EmotionChip extends StatelessWidget {
  const _EmotionChip({required this.record});

  final Record record;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: AppColors.paleMint,
        borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
      ),
      child: Text('${record.emotion.emoji} ${record.emotion.displayName}'),
    );
  }
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
      ),
      child: Text(
        label,
        style: const TextStyle(color: AppColors.muted, fontSize: 12),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
