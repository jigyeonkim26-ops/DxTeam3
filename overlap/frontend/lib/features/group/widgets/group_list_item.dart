import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../models/group_list_item_data.dart';

class GroupListItem extends StatelessWidget {
  const GroupListItem({
    super.key,
    required this.group,
    required this.isSelected,
    required this.onTap,
    required this.onShare,
  });

  final GroupListItemData group;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final title = isSelected ? '${group.name} · 현재 선택됨' : group.name;
    final summary = [
      '멤버 ${group.memberCount}명 · ${group.placeCountDescription}',
      if (group.newRecordDescription.isNotEmpty) group.newRecordDescription,
    ].join(' · ');

    return Semantics(
      button: true,
      selected: isSelected,
      label: '$title, $summary',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              border: const Border(
                bottom: BorderSide(color: AppColors.divider),
              ),
              color: isSelected
                  ? AppColors.paleMint.withValues(alpha: 0.45)
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: AppColors.ink,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          summary,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontSize: 12, height: 1.55),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  IconButton(
                    onPressed: onShare,
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFF2F4F5),
                      foregroundColor: AppColors.deepNavy,
                      minimumSize: const Size(36, 36),
                      padding: EdgeInsets.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.ios_share_outlined, size: 18),
                    tooltip: '${group.name} 공유',
                  ),
                  if (isSelected)
                    const Icon(
                      Icons.check_circle,
                      color: AppColors.deepNavy,
                      size: 20,
                      semanticLabel: '현재 선택됨',
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
