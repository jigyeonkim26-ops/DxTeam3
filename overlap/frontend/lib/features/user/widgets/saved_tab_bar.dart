import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../models/saved_item_data.dart';

class SavedTabBar extends StatelessWidget {
  const SavedTabBar({
    super.key,
    required this.selectedType,
    required this.onSelected,
  });
  final SavedItemType selectedType;
  final ValueChanged<SavedItemType> onSelected;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: _Tab(
          label: '가보고 싶은 곳',
          selected: selectedType == SavedItemType.wishPlace,
          onTap: () => onSelected(SavedItemType.wishPlace),
        ),
      ),
      const SizedBox(width: AppSpacing.xs),
      Expanded(
        child: _Tab(
          label: '내 기록',
          selected: selectedType == SavedItemType.myRecord,
          onTap: () => onSelected(SavedItemType.myRecord),
        ),
      ),
    ],
  );
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
    child: Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: BoxDecoration(
        color: selected ? AppColors.coral : AppColors.paleMint,
        borderRadius: const BorderRadius.all(
          Radius.circular(AppSpacing.buttonRadius),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : AppColors.deepNavy,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}
