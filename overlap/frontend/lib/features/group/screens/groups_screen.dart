import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../models/group_list_item_data.dart';
import '../services/mock_group_repository.dart';
import '../widgets/group_list_item.dart';
import 'create_group_screen.dart';
import 'join_group_screen.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key, required this.onShowGroupOnMap});

  final ValueChanged<String> onShowGroupOnMap;

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  String? _selectedGroupId;
  final _inviteCodeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final groups = MockGroupRepository.groups;
    if (groups.isNotEmpty) {
      _selectedGroupId = groups
          .firstWhere(
            (group) => group.isInitiallySelected,
            orElse: () => groups.first,
          )
          .id;
    }
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

  void _openShareSheet(GroupListItemData group) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Material(
          color: AppColors.paper,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppSpacing.cardRadius),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.all(
                        Radius.circular(AppSpacing.pillRadius),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  '${group.name} 초대',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  '친구에게 이 링크를 보내 모임에 초대해보세요.',
                  style: TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    border: Border(
                      top: BorderSide(color: AppColors.divider),
                      right: BorderSide(color: AppColors.divider),
                      bottom: BorderSide(color: AppColors.divider),
                      left: BorderSide(color: AppColors.divider),
                    ),
                    borderRadius: BorderRadius.all(
                      Radius.circular(AppSpacing.buttonRadius),
                    ),
                  ),
                  child: Text(
                    group.inviteUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.deepNavy,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: group.inviteUrl),
                      );
                      if (!mounted || !sheetContext.mounted) return;
                      Navigator.pop(sheetContext);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('초대 링크를 복사했습니다.')),
                      );
                    },
                    icon: const Icon(Icons.content_copy_outlined),
                    label: const Text('링크 복사'),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('실제 시스템 공유 기능을 위해 share_plus 추가가 필요합니다.'),
                      ),
                    ),
                    icon: const Icon(Icons.ios_share_outlined),
                    label: const Text('공유하기'),
                  ),
                ),
              ],
            ),
          ),
        ),
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
          ValueListenableBuilder<List<GroupListItemData>>(
            valueListenable: MockGroupRepository.groupsListenable,
            builder: (context, groups, _) {
              if (groups.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Text(
                    '참여 중인 모임이 없어요.',
                    style: TextStyle(color: AppColors.muted),
                  ),
                );
              }

              return Column(
                children: [
                  for (final group in groups)
                    GroupListItem(
                      group: group,
                      isSelected: group.id == _selectedGroupId,
                      onTap: () {
                        setState(() => _selectedGroupId = group.id);
                        widget.onShowGroupOnMap(group.id);
                      },
                      onShare: () => _openShareSheet(group),
                    ),
                ],
              );
            },
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
