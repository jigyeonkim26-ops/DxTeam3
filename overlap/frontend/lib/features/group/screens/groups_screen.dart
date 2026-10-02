import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../models/group_list_item_data.dart';
import '../services/mock_group_repository.dart';
import '../widgets/group_list_item.dart';
import 'create_group_screen.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  late final List<GroupListItemData> _groups;
  late String _selectedGroupId;

  @override
  void initState() {
    super.initState();
    _groups = MockGroupRepository.groups;
    _selectedGroupId = _groups
        .firstWhere((group) => group.isInitiallySelected)
        .id;
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.paper,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        children: [
          Text(
            '함께 쌓는 장소',
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontSize: 27, height: 1.25),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '참여 중인 모임의 기록은 모임 안에서만 볼 수 있어요.\n피드는 하단 피드 탭에서 확인합니다.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(height: 1.65),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Text(
                '내 모임',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CreateGroupScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('모임 만들기'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ..._groups.map(
            (group) => GroupListItem(
              group: group,
              isSelected: group.id == _selectedGroupId,
              onTap: () => setState(() => _selectedGroupId = group.id),
            ),
          ),
        ],
      ),
    );
  }
}
