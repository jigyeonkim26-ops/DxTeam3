import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';

class NotificationSettingTile extends StatelessWidget {
  const NotificationSettingTile({
    super.key,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });
  final String title, description;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext c) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.divider)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(c).textTheme.bodyLarge
                    ?.copyWith(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                description,
                style: Theme.of(c).textTheme.bodyMedium
                    ?.copyWith(fontSize: 11, height: 1.45),
              ),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    ),
  );
}
