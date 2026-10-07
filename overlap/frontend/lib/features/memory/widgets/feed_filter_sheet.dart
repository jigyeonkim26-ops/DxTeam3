import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../models/feed_filter.dart';

class FeedFilterSheet extends StatefulWidget {
  const FeedFilterSheet({super.key, required this.selectedFilters});

  final Set<FeedFilter> selectedFilters;

  @override
  State<FeedFilterSheet> createState() => _FeedFilterSheetState();
}

class _FeedFilterSheetState extends State<FeedFilterSheet> {
  late final Set<FeedFilter> _filters = {...widget.selectedFilters}
    ..remove(FeedFilter.all);

  bool get _isAllSelected =>
      _filters.length == FeedFilter.selectableFilters.length &&
      _filters.containsAll(FeedFilter.selectableFilters);

  void _toggleAll(bool selected) {
    setState(() {
      _filters.clear();
      if (selected) _filters.addAll(FeedFilter.selectableFilters);
    });
  }

  void _toggleFilter(FeedFilter filter, bool selected) {
    setState(() {
      if (selected) {
        _filters.add(filter);
        return;
      }
      _filters.remove(filter);
    });
  }

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
                  '내 기록과 여러 모임의 기록을 함께 볼 수 있어요.',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              CheckboxListTile(
                value: _isAllSelected,
                onChanged: (selected) => _toggleAll(selected ?? false),
                activeColor: AppColors.deepNavy,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.trailing,
                title: const Text(
                  '전체',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              for (final filter in FeedFilter.selectableFilters)
                CheckboxListTile(
                  value: _filters.contains(filter),
                  onChanged: (selected) =>
                      _toggleFilter(filter, selected ?? false),
                  activeColor: AppColors.deepNavy,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.trailing,
                  title: Text(
                    filter.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _filters.isEmpty
                      ? null
                      : () => Navigator.pop(context, Set.of(_filters)),
                  child: const Text('필터 적용하기'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
