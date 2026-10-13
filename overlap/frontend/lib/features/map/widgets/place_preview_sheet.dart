import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../ai/models/ai_place_recommendation.dart';
import '../models/map_place.dart';

class PlacePreviewSheet extends StatelessWidget {
  const PlacePreviewSheet({
    super.key,
    required this.place,
    required this.onViewDetails,
  }) : recommendation = null;

  const PlacePreviewSheet.recommendation({
    super.key,
    required this.recommendation,
    required this.onViewDetails,
  }) : place = null;

  final MapPlace? place;
  final AiPlaceRecommendation? recommendation;
  final VoidCallback onViewDetails;

  @override
  Widget build(BuildContext context) {
    final recordedPlace = place;
    final aiPlace = recommendation;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        decoration: const BoxDecoration(
          color: AppColors.paper,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.cardRadius),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              aiPlace == null ? 'OVERLAPPED PLACE' : 'AI 추천 장소',
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Row(
              children: [
                Expanded(
                  child: Text(
                    aiPlace?.name ?? recordedPlace!.name,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.8,
                    ),
                  ),
                ),
                if (recordedPlace != null) Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.paleMint,
                    borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
                  ),
                  child: Text('${recordedPlace.recordCount}개의 기록'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (aiPlace != null)
              Text(
                aiPlace.address ?? '주소 정보 없음',
                style: const TextStyle(color: AppColors.muted),
              )
            else ...[
              Text(
                recordedPlace!.author,
                style: const TextStyle(
                  color: AppColors.deepNavy,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(recordedPlace.summary, style: const TextStyle(color: AppColors.muted)),
            ],
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onViewDetails,
                child: const Text('장소 상세 보기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
