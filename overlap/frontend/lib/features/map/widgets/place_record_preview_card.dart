import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/record.dart';

/// 장소 상세 안에서 해당 장소의 기록을 미리 보여주는 카드입니다.
class PlaceRecordPreviewCard extends StatelessWidget {
  const PlaceRecordPreviewCard({
    super.key,
    required this.record,
    required this.onTap,
  });

  final Record record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 19,
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
                    style: const TextStyle(fontSize: 23),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              _PhotoPlaceholder(record: record),
              const SizedBox(height: AppSpacing.sm),
              Text(record.content, style: const TextStyle(height: 1.5)),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  _Chip(
                    label:
                        '${record.emotion.emoji} ${record.emotion.displayName}',
                  ),
                  for (final group in record.sharedGroups)
                    _Chip(label: group.name),
                ],
              ),
              const Divider(height: AppSpacing.lg),
              Row(
                children: [
                  _MetaAction(
                    icon: Icons.favorite_border,
                    label: '공감 ${record.likeCount}',
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  _MetaAction(
                    icon: Icons.chat_bubble_outline,
                    label: '댓글 ${record.commentCount}',
                  ),
                ],
              ),
            ],
          ),
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

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({required this.record});

  final Record record;

  @override
  Widget build(BuildContext context) {
    final colors = switch (record.id) {
      'place-record-sun' => const [Color(0xFFE9B67A), Color(0xFFFF7058)],
      'place-record-rain' => const [Color(0xFF86A7B6), AppColors.deepNavy],
      _ => const [Color(0xFF9FC4B2), Color(0xFF5C8474)],
    };
    return Container(
      height: 174,
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
          padding: EdgeInsets.all(AppSpacing.sm),
          child: Icon(Icons.image_outlined, color: Colors.white70),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

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
      child: Text(
        label,
        style: const TextStyle(color: AppColors.deepNavy, fontSize: 12),
      ),
    );
  }
}

class _MetaAction extends StatelessWidget {
  const _MetaAction({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppColors.muted, size: 18),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
