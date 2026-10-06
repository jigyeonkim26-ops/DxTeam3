import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';

class ShareCardChip extends StatelessWidget {
  const ShareCardChip({super.key, required this.label});
  final String label;
  @override
  Widget build(BuildContext c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 7),
    decoration: const BoxDecoration(
      color: AppColors.paleMint,
      borderRadius: BorderRadius.all(Radius.circular(AppSpacing.pillRadius)),
    ),
    child: Text(
      label,
      style: const TextStyle(
        color: AppColors.deepNavy,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}
