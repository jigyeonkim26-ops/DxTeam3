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
    required this.onChanged,
  });

  final List<Group> groups;
  final Set<String> selectedGroupIds;
  final bool isDisabled;
  final ValueChanged<Group> onChanged;

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
                for (final group in groups)
                  CheckboxListTile(
                    value: selectedGroupIds.contains(group.id),
                    onChanged: (_) => onChanged(group),
                    activeColor: AppColors.deepNavy,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                    controlAffinity: ListTileControlAffinity.trailing,
                    title: Text(
                      group.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text('멤버 ${group.memberCount}명'),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
