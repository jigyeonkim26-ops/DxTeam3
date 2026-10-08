import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../group/models/group_list_item_data.dart';
import '../../group/services/group_list_store.dart';
import '../../group/services/group_api_service.dart';
import '../../../core/network/api_transport.dart';

class GroupManagementScreen extends StatefulWidget {
  const GroupManagementScreen({super.key});

  @override
  State<GroupManagementScreen> createState() => _GroupManagementScreenState();
}

class _GroupManagementScreenState extends State<GroupManagementScreen> {
  String? _selectedGroupId;
  bool _isLoading = true;
  bool _isLeaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await GroupListStore.refreshGroups();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = '모임 목록을 불러오지 못했습니다.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmLeave(GroupListItemData group) async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('모임에서 탈퇴할까요?'),
        content: Text("'${group.name}'에서 탈퇴하면\n더 이상 이 모임의 기록을 함께 볼 수 없습니다."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.coral),
            child: const Text('탈퇴하기'),
          ),
        ],
      ),
    );

    if (shouldLeave != true || !mounted || _isLeaving) return;

    setState(() => _isLeaving = true);
    try {
      await GroupApiService.leaveGroup(int.parse(group.id));
      GroupListStore.removeGroupFromCache(group.id);
      if (!mounted) return;
      setState(() => _selectedGroupId = null);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('${group.name}에서 탈퇴했습니다.')));
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('탈퇴 요청을 처리하지 못했습니다.')));
      }
    } finally {
      if (mounted) setState(() => _isLeaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        title: const Text('내 모임 관리'),
        backgroundColor: AppColors.paper,
        surfaceTintColor: AppColors.paper,
      ),
      body: ValueListenableBuilder<List<GroupListItemData>>(
        valueListenable: GroupListStore.groupsListenable,
        builder: (context, groups, _) {
          GroupListItemData? selectedGroup;
          for (final group in groups) {
            if (group.id == _selectedGroupId) {
              selectedGroup = group;
              break;
            }
          }

          return SafeArea(
            top: false,
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    children: [
                      Text(
                        '참여 중인 모임',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      const Text(
                        '탈퇴할 모임을 하나 선택해 주세요.',
                        style: TextStyle(color: AppColors.muted),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (_isLoading) const LinearProgressIndicator(),
                      if (_error != null)
                        TextButton(
                          onPressed: _reload,
                          child: Text('$_error 다시 시도'),
                        ),
                      if (groups.isEmpty && !_isLoading && _error == null)
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: AppSpacing.xl,
                          ),
                          child: Center(
                            child: Text(
                              '참여 중인 모임이 없어요.',
                              style: TextStyle(color: AppColors.muted),
                            ),
                          ),
                        )
                      else
                        ...groups.map(
                          (group) => _GroupSelectionRow(
                            group: group,
                            isSelected: group.id == _selectedGroupId,
                            onTap: () =>
                                setState(() => _selectedGroupId = group.id),
                          ),
                        ),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.sm,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: selectedGroup == null || _isLeaving
                            ? null
                            : () => _confirmLeave(selectedGroup!),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.coral,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.divider,
                          disabledForegroundColor: AppColors.muted,
                        ),
                        child: const Text('모임 탈퇴하기'),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _GroupSelectionRow extends StatelessWidget {
  const _GroupSelectionRow({
    required this.group,
    required this.isSelected,
    required this.onTap,
  });

  final GroupListItemData group;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? AppColors.paleMint : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.md,
          ),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.divider)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '멤버 ${group.memberCount}명 · 장소 ${group.placeCount}곳',
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: isSelected ? AppColors.deepNavy : AppColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
