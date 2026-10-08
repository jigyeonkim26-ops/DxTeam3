import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/network/api_config.dart';
import '../../../core/network/api_transport.dart';
import '../../../shared/models/record.dart';
import 'record_photo.dart';

class RecordCard extends StatelessWidget {
  const RecordCard({
    super.key,
    required this.record,
    required this.isLiked,
    required this.onTap,
    required this.onLikeTap,
    required this.onCommentTap,
    required this.onPlaceTap,
    this.likeCount,
    this.isLikeLoading = false,
  });

  final Record record;
  final bool isLiked;
  final VoidCallback onTap;
  final VoidCallback onLikeTap;
  final VoidCallback onCommentTap;
  final VoidCallback onPlaceTap;
  final int? likeCount;
  final bool isLikeLoading;

  @override
  Widget build(BuildContext context) {
    final displayLikeCount = likeCount ?? record.likeCount;
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
                  _Avatar(
                    name: record.author.name,
                    profileImagePath: record.author.profileImagePath,
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
              if (record.imagePaths.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                RecordPhoto(paths: record.imagePaths),
                const SizedBox(height: AppSpacing.sm),
              ],
              const SizedBox(height: AppSpacing.xs),
              Text(record.content, style: const TextStyle(height: 1.5)),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  if (record.isPrivate) const _GroupChip(label: '나만 보기'),
                  for (final group in record.sharedGroups)
                    _GroupChip(label: group.name),
                ],
              ),
              const Divider(height: AppSpacing.lg),
              Row(
                children: [
                  _ActionButton(
                    icon: isLiked ? Icons.favorite : Icons.favorite_border,
                    label: '공감 $displayLikeCount',
                    color: isLiked ? AppColors.coral : AppColors.muted,
                    onTap: isLikeLoading ? null : onLikeTap,
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
  const _Avatar({required this.name, this.profileImagePath});

  final String name;
  final String? profileImagePath;

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name.substring(0, 1);
    final token = ApiTransport.accessToken;
    final path = profileImagePath;
    final imageUrl = path == null || path.isEmpty
        ? null
        : path.startsWith('http://') || path.startsWith('https://')
        ? path
        : '${ApiConfig.baseUrl}$path';
    final provider = imageUrl == null || token == null || token.isEmpty
        ? null
        : NetworkImage(imageUrl, headers: {'Authorization': 'Bearer $token'});

    return CircleAvatar(
      radius: 20,
      backgroundColor: AppColors.softMint,
      foregroundColor: AppColors.deepNavy,
      child: provider == null
          ? _AvatarInitial(initial: initial)
          : ClipOval(
              child: SizedBox.expand(
                child: Image(
                  image: provider,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _AvatarInitial(initial: initial),
                ),
              ),
            ),
    );
  }
}

class _AvatarInitial extends StatelessWidget {
  const _AvatarInitial({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) => Text(
    initial,
    style: const TextStyle(fontWeight: FontWeight.w700),
  );
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
  final VoidCallback? onTap;

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
