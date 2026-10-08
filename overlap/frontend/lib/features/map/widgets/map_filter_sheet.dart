import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../models/map_filter.dart';

class MapFilterSheet extends StatefulWidget {
  const MapFilterSheet({
    super.key,
    required this.selectedFilters,
    required this.availableFilters,
  });

  final Set<MapFilter> selectedFilters;
  final List<MapFilter> availableFilters;

  @override
  State<MapFilterSheet> createState() => _MapFilterSheetState();
}

class _MapFilterSheetState extends State<MapFilterSheet> {
  late final Set<MapFilter> _filters = {...widget.selectedFilters};

  bool get _isAllSelected =>
      _filters.length == widget.availableFilters.length &&
      _filters.containsAll(widget.availableFilters);

  @override
  Widget build(BuildContext context) {
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
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
        ),
        child: SingleChildScrollView(
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
                  '지도에 표시할 기록',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '여러 모임의 기록을 함께 볼 수 있어요.',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              CheckboxListTile(
                value: _isAllSelected,
                onChanged: (selected) => setState(() {
                  _filters
                    ..clear()
                    ..addAll(
                      selected ?? false ? widget.availableFilters : const [],
                    );
                }),
                activeColor: AppColors.deepNavy,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.trailing,
                title: const Text(
                  '전체',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              for (final filter in widget.availableFilters)
                CheckboxListTile(
                  value: _filters.contains(filter),
                  onChanged: (selected) => setState(() {
                    if (selected ?? false) {
                      _filters.add(filter);
                    } else {
                      _filters.remove(filter);
                    }
                  }),
                  activeColor: AppColors.deepNavy,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.trailing,
                  secondary: Icon(
                    Icons.circle,
                    size: 14,
                    color: Color(filter.pinColorValue ?? 0xFF14364A),
                  ),
                  title: Text(
                    filter.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, _filters),
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
