import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../models/profile_summary_data.dart';

class ProfileSummaryCard extends StatelessWidget {
  const ProfileSummaryCard({super.key, required this.profile});
  final ProfileSummaryData profile;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.lg),
    decoration: const BoxDecoration(
      color: AppColors.deepNavy,
      borderRadius: BorderRadius.all(Radius.circular(AppSpacing.cardRadius)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CircleAvatar(
          radius: 22,
          backgroundColor: AppColors.softMint,
          child: Icon(Icons.person, color: AppColors.deepNavy),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          profile.userName,
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          profile.statusText,
          style: const TextStyle(color: AppColors.paleMint, fontSize: 12),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            _Stat(profile.recordCount, '내 기록'),
            _Stat(profile.visitedPlaceCount, '방문 장소'),
            _Stat(profile.groupCount, '내 모임'),
          ],
        ),
      ],
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label);
  final int value;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          '$value',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: AppColors.paleMint, fontSize: 10),
        ),
      ],
    ),
  );
}
