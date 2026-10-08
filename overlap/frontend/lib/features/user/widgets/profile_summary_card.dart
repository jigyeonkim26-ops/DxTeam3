import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../models/profile_summary_data.dart';
import 'profile_photo_avatar.dart';

class ProfileSummaryCard extends StatelessWidget {
  const ProfileSummaryCard({
    super.key,
    required this.profile,
    this.onProfileTap,
    this.onRecordsTap,
    this.photoRevision = 0,
  });

  final ProfileSummaryData profile;
  final VoidCallback? onProfileTap;
  final VoidCallback? onRecordsTap;
  final int photoRevision;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
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
                    ProfilePhotoAvatar(
                      radius: 50,
                      iconSize: 36,
                      revision: photoRevision,
                    ),
                    Positioned(
                      right: -1,
                      bottom: -1,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.coral,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.edit,
                          color: Colors.white,
                          size: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                profile.userName,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppColors.deepNavy,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
          ),
          child: Row(
            children: [
              _Stat(profile.recordCount, '내 기록', onTap: onRecordsTap),
              _Stat(profile.visitedPlaceCount, '방문 장소'),
              _Stat(profile.groupCount, '내 모임'),
            ],
          ),
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
            color: AppColors.deepNavy,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: AppColors.muted, fontSize: 10),
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
