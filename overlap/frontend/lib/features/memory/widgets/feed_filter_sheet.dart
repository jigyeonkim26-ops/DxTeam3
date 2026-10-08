import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/group.dart';

class FeedFilterSheet extends StatefulWidget {
  const FeedFilterSheet({
    super.key,
    required this.selectedFilters,
    required this.groups,
  });

  final Set<String> selectedFilters;
  final List<Group> groups;

  @override
  State<FeedFilterSheet> createState() => _FeedFilterSheetState();
}

class _FeedFilterSheetState extends State<FeedFilterSheet> {
  late final Set<String> _filters = widget.selectedFilters.contains('all')
      ? _options.keys.toSet()
      : {...widget.selectedFilters};

  Map<String, String> get _options => {
    'mine': '내 기록만 보기',
    for (final group in widget.groups) group.id: group.name,
  };

  bool get _isAllSelected =>
      _filters.length == _options.length && _filters.containsAll(_options.keys);

  void _toggleAll(bool selected) {
    setState(() {
      _filters.clear();
      if (selected) _filters.addAll(_options.keys);
    });
  }

  void _toggleFilter(String filter, bool selected) {
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
        child: SingleChildScrollView(
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
                for (final filter in _options.entries)
                  CheckboxListTile(
                    value: _filters.contains(filter.key),
                    onChanged: (selected) =>
                        _toggleFilter(filter.key, selected ?? false),
                    activeColor: AppColors.deepNavy,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.trailing,
                    title: Text(
                      filter.value,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _filters.isEmpty
                        ? null
                        : () => Navigator.pop(
                            context,
                            _isAllSelected ? <String>{'all'} : Set.of(_filters),
                          ),
                    child: const Text('필터 적용하기'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
