import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../models/group_list_item_data.dart';
import '../services/mock_group_repository.dart';
import '../widgets/group_list_item.dart';
import 'create_group_screen.dart';
import 'join_group_screen.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  late final List<GroupListItemData> _groups;
  late String _selectedGroupId;
  final _inviteCodeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _groups = MockGroupRepository.groups;
    _selectedGroupId = _groups
        .firstWhere((group) => group.isInitiallySelected)
        .id;
  }

  @override
  void dispose() {
    _inviteCodeController.dispose();
    super.dispose();
  }

  void _openJoinGroupScreen() {
    final inviteCode = _inviteCodeController.text.trim();
    if (inviteCode.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('초대 코드를 입력해 주세요.')));
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => JoinGroupScreen(inviteCode: inviteCode),
      ),
    );
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
          const SizedBox(height: AppSpacing.lg),
          const Divider(),
          const SizedBox(height: AppSpacing.lg),
          Text(
            '모임 참여',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '방장님에게 받은 초대 코드를 입력해 참여할 수 있어요. 공유 링크를 열면 바로 참여 확인 화면으로 연결됩니다.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(height: 1.65),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('초대 코드로 참여', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            controller: _inviteCodeController,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _openJoinGroupScreen(),
            decoration: const InputDecoration(hintText: '예: YN-2026'),
          ),
          const SizedBox(height: AppSpacing.xs),
          OutlinedButton(
            onPressed: _openJoinGroupScreen,
            child: const Text('코드로 참여하기'),
          ),
        ],
      ),
    );
  }
}
