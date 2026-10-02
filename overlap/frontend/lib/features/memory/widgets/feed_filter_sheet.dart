import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../models/feed_filter.dart';

class FeedFilterSheet extends StatelessWidget {
  const FeedFilterSheet({super.key, required this.selectedFilter});

  final FeedFilter selectedFilter;

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
              RadioGroup<FeedFilter>(
                groupValue: selectedFilter,
                onChanged: (value) => Navigator.pop(context, value),
                child: Column(
                  children: [
                    for (final filter in FeedFilter.values)
                      RadioListTile<FeedFilter>(
                        value: filter,
                        activeColor: AppColors.deepNavy,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          filter.label,
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
