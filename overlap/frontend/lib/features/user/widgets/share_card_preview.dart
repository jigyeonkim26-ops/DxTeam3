import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../models/share_card_data.dart';

class ShareCardPreview extends StatelessWidget {
  const ShareCardPreview({super.key, required this.data});
  final ShareCardData data;
  @override
  Widget build(BuildContext c) => AspectRatio(
    aspectRatio: 1,
    child: Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.paleMint, AppColors.paper],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.all(Radius.circular(AppSpacing.cardRadius)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'OVERLAP · ${data.dateText}',
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Container(
            height: 72,
            width: double.infinity,
            decoration: const BoxDecoration(
              color: AppColors.softMint,
              borderRadius: BorderRadius.all(
                Radius.circular(AppSpacing.buttonRadius),
              ),
            ),
            child: const Icon(
              Icons.photo_outlined,
              color: AppColors.deepNavy,
              size: 30,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            data.placeName,
            style: Theme.of(c).textTheme.headlineSmall
                ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            data.memoryText,
            style: Theme.of(c).textTheme.bodyLarge
                ?.copyWith(color: AppColors.deepNavy),
          ),
        ],
      ),
    ),
  );
}
