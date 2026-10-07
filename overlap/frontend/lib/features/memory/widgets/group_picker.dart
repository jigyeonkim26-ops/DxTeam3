import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/group.dart';

class GroupPicker extends StatelessWidget {
  const GroupPicker({
    super.key,
    required this.groups,
    required this.selectedGroupIds,
    required this.isDisabled,
    required this.areAllSelected,
    required this.onChanged,
    required this.onSelectAll,
  });

  final List<Group> groups;
  final Set<String> selectedGroupIds;
  final bool isDisabled;
  final bool areAllSelected;
  final ValueChanged<Group> onChanged;
  final ValueChanged<bool> onSelectAll;

  static const _scrollThreshold = 4;
  static const _scrollListHeight = 240.0;

  Widget _buildGroupTile(Group group) {
    return CheckboxListTile(
      value: selectedGroupIds.contains(group.id),
      onChanged: (_) => onChanged(group),
      activeColor: AppColors.deepNavy,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      controlAffinity: ListTileControlAffinity.trailing,
      title: Text(
        group.name,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text('멤버 ${group.memberCount}명'),
    );
  }

  Widget _buildGroupList() {
    if (groups.length < _scrollThreshold) {
      return Column(
        children: [for (final group in groups) _buildGroupTile(group)],
      );
    }

    return SizedBox(
      height: _scrollListHeight,
      child: ListView.builder(
        primary: false,
        padding: EdgeInsets.zero,
        itemCount: groups.length,
        itemBuilder: (context, index) => _buildGroupTile(groups[index]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isDisabled ? 0.48 : 1,
      child: AbsorbPointer(
        absorbing: isDisabled,
        child: Card(
          color: AppColors.surface,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              children: [
                CheckboxListTile(
                  value: areAllSelected,
                  onChanged: isDisabled
                      ? null
                      : (selected) => onSelectAll(selected ?? false),
                  activeColor: AppColors.deepNavy,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                  controlAffinity: ListTileControlAffinity.trailing,
                  title: const Text(
                    '전체 선택',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const Divider(height: 1, color: AppColors.divider),
                _buildGroupList(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
