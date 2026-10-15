import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../models/nearby_reminder.dart';

class NearbyReminderBanner extends StatelessWidget {
  const NearbyReminderBanner({
    super.key,
    required this.reminder,
    required this.onTap,
    required this.onDismiss,
  });

  final NearbyReminder reminder;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    elevation: 3,
    borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.sm,
        ),
        child: Row(
          children: [
            const Icon(Icons.history, color: AppColors.coral),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '근처에 기록한 장소가 있어요',
                    style: TextStyle(
                      color: AppColors.deepNavy,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${reminder.record.place.name} · ${reminder.distanceMeters}m',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '닫기',
              onPressed: onDismiss,
              icon: const Icon(Icons.close, size: 18),
            ),
          ],
        ),
      ),
    ),
  );
}
