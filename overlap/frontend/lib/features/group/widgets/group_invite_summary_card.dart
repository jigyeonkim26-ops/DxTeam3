import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../models/group_invite_preview.dart';

class GroupInviteSummaryCard extends StatelessWidget {
  const GroupInviteSummaryCard({super.key, required this.preview});

  final GroupInvitePreview preview;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.softMint,
              child: Icon(Icons.groups_outlined, color: AppColors.deepNavy),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preview.groupName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    '방장 ${preview.ownerName} · 멤버 ${preview.memberCount}명 · 장소 기록 ${preview.placeCount}개',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(fontSize: 12, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
