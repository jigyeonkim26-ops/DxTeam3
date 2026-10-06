import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';

class InviteInfoCard extends StatelessWidget {
  const InviteInfoCard({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.copyLabel,
    required this.onCopy,
  });

  final String title;
  final String description;
  final String value;
  final String copyLabel;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              description,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontSize: 12, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: const BoxDecoration(
                color: AppColors.paleMint,
                borderRadius: BorderRadius.all(Radius.circular(AppSpacing.xs)),
              ),
              child: SelectableText(
                value,
                style: const TextStyle(
                  color: AppColors.deepNavy,
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: onCopy,
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: Text(copyLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
