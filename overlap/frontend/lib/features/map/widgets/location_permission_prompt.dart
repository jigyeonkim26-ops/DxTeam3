import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';

enum LocationPermissionChoice { all, whileUsing, deny }

Future<LocationPermissionChoice?> showLocationPermissionPrompt(
  BuildContext context,
) {
  return showModalBottomSheet<LocationPermissionChoice>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (context) => SafeArea(
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
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              '위치 접근을 허용할까요?',
              style: TextStyle(
                color: AppColors.deepNavy,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'OVERLAP은 현재 위치를 확인하고\n기록한 장소를 지도에 표시하기 위해 위치 정보를 사용합니다.',
              style: TextStyle(color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(
              onPressed: () =>
                  Navigator.pop(context, LocationPermissionChoice.all),
              child: const Text('전체 허용'),
            ),
            const SizedBox(height: AppSpacing.xs),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(context, LocationPermissionChoice.whileUsing),
              child: const Text('앱을 사용하는 동안만 허용'),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, LocationPermissionChoice.deny),
              child: const Text('허용하지 않음'),
            ),
          ],
        ),
      ),
    ),
  );
}
