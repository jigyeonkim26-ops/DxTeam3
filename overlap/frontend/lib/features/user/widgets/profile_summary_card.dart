import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../models/profile_summary_data.dart';

class ProfileSummaryCard extends StatelessWidget {
  const ProfileSummaryCard({
    super.key,
    required this.profile,
    this.onProfileTap,
    this.onRecordsTap,
    this.profileImagePath,
  });

  final ProfileSummaryData profile;
  final VoidCallback? onProfileTap;
  final VoidCallback? onRecordsTap;
  final String? profileImagePath;
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
        Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onProfileTap,
            customBorder: const CircleBorder(),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.softMint,
                  backgroundImage: profileImagePath == null
                      ? null
                      : FileImage(File(profileImagePath!)),
                  child: profileImagePath == null
                      ? const Icon(Icons.person, color: AppColors.deepNavy)
                      : null,
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: AppColors.coral,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.edit,
                      color: Colors.white,
                      size: 11,
                    ),
                  ),
                ),
              ],
            ),
          ),
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
            _Stat(profile.recordCount, '내 기록', onTap: onRecordsTap),
            _Stat(profile.visitedPlaceCount, '방문 장소'),
            _Stat(profile.groupCount, '내 모임'),
          ],
        ),
      ],
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, {this.onTap});

  final int value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Column(
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
    );

    return Expanded(
      child: onTap == null
          ? content
          : Semantics(
              button: true,
              label: label,
              child: Material(
                color: Colors.transparent,
                child: InkWell(onTap: onTap, child: content),
              ),
            ),
    );
  }
}
