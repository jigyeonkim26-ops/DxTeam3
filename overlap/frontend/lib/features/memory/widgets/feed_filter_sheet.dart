import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/group.dart';

class FeedFilterSheet extends StatelessWidget {
  const FeedFilterSheet({
    super.key,
    required this.selectedFilter,
    required this.groups,
  });

  final String selectedFilter;
  final List<Group> groups;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Material(
        color: AppColors.paper,
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSpacing.cardRadius),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '피드에 표시할 기록',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '모임 하나 또는 내 기록만 선택할 수 있어요.',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              RadioGroup<String>(
                groupValue: selectedFilter,
                onChanged: (value) => Navigator.pop(context, value),
                child: Column(
                  children: [
                    for (final filter in {
                      'all': '내 맞춤 피드',
                      'mine': '내 기록만 보기',
                      for (final group in groups) group.id: group.name,
                    }.entries)
                      RadioListTile<String>(
                        value: filter.key,
                        activeColor: AppColors.deepNavy,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          filter.value,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
