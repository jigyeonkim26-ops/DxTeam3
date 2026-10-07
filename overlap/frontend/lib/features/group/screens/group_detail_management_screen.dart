import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../models/group_list_item_data.dart';
import '../services/mock_group_repository.dart';

class GroupDetailManagementScreen extends StatefulWidget {
  const GroupDetailManagementScreen({super.key, required this.groupId});

  final String groupId;

  @override
  State<GroupDetailManagementScreen> createState() =>
      _GroupDetailManagementScreenState();
}

class _GroupDetailManagementScreenState
    extends State<GroupDetailManagementScreen> {
  static const _pinColors = <Color>[
    AppColors.coral,
    AppColors.deepNavy,
    Color(0xFF6FAE8F),
    Color(0xFFF0B35D),
    Color(0xFF8C7BBD),
  ];

  final _nameController = TextEditingController();
  bool _isEditingName = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _startEditingName(GroupListItemData group) {
    setState(() {
      _nameController.text = group.name;
      _isEditingName = true;
    });
  }

  void _cancelEditingName() {
    setState(() => _isEditingName = false);
  }

  void _saveName(GroupListItemData group) {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('모임 이름을 입력해 주세요.')));
      return;
    }

    MockGroupRepository.updateGroup(group.copyWith(name: name));
    setState(() => _isEditingName = false);
  }

  void _toggleNotifications(GroupListItemData group) {
    final isEnabled = !(group.notificationsEnabled ?? true);
    MockGroupRepository.updateGroup(
      group.copyWith(notificationsEnabled: isEnabled),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${group.name} 알림을 ${isEnabled ? '켰습니다.' : '껐습니다.'}'),
      ),
    );
  }

  void _updatePinColor(GroupListItemData group, Color color) {
    MockGroupRepository.updateGroup(
      group.copyWith(pinColorValue: color.toARGB32()),
    );
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

    if (shouldLeave != true || !mounted) return;
    if (!MockGroupRepository.leaveGroup(group.id)) return;

    Navigator.of(context).pop(group.name);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<GroupListItemData>>(
      valueListenable: MockGroupRepository.groupsListenable,
      builder: (context, groups, _) {
        final group = groups
            .where((item) => item.id == widget.groupId)
            .firstOrNull;
        if (group == null) {
          return const Scaffold(
            body: SafeArea(child: Center(child: Text('모임 정보를 찾을 수 없어요.'))),
          );
        }

        final isNotificationsEnabled = group.notificationsEnabled ?? true;
        final pinColorValue = group.pinColorValue ?? AppColors.coral.toARGB32();
        final recordCount = group.recordCount ?? 0;
        final members = MockGroupRepository.membersFor(group);
        final memberCount = members.isEmpty
            ? group.memberCount
            : members.length;

        return Scaffold(
          backgroundColor: AppColors.paper,
          appBar: AppBar(
            title: const Text('모임 관리'),
            backgroundColor: AppColors.paper,
            surfaceTintColor: AppColors.paper,
            actions: [
              IconButton(
                tooltip: isNotificationsEnabled ? '알림 끄기' : '알림 켜기',
                onPressed: () => _toggleNotifications(group),
                icon: Icon(
                  isNotificationsEnabled
                      ? Icons.notifications_outlined
                      : Icons.notifications_off_outlined,
                ),
              ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              children: [
                _GroupNameEditor(
                  group: group,
                  controller: _nameController,
                  isEditing: _isEditingName,
                  onStartEditing: () => _startEditingName(group),
                  onCancel: _cancelEditingName,
                  onSave: () => _saveName(group),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '멤버 $memberCount명  ·  장소 ${group.placeCount}곳  ·  기록 $recordCount개',
                  style: const TextStyle(color: AppColors.muted),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  '핀 색상',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final color in _pinColors)
                      _PinColorButton(
                        color: color,
                        isSelected: color.toARGB32() == pinColorValue,
                        onTap: () => _updatePinColor(group, color),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  '멤버',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                for (final member in members) _GroupMemberRow(member: member),
                if (members.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Text(
                      '현재 표시할 멤버 정보가 없어요.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),
                const Divider(),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => _confirmLeave(group),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.coral,
                    ),
                    child: const Text('모임 탈퇴하기'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GroupMemberRow extends StatelessWidget {
  const _GroupMemberRow({required this.member});

  final GroupMemberData member;

  @override
  Widget build(BuildContext context) {
    final initial = member.nickname.isEmpty
        ? '?'
        : member.nickname.substring(0, 1);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.paleMint,
            foregroundColor: AppColors.deepNavy,
            child: member.profileImagePath == null
                ? _MemberInitial(initial: initial)
                : ClipOval(
                    child: SizedBox.expand(
                      child: Image.asset(
                        member.profileImagePath!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            _MemberInitial(initial: initial),
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            member.nickname,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: AppColors.deepNavy,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberInitial extends StatelessWidget {
  const _MemberInitial({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    return Text(initial, style: const TextStyle(fontWeight: FontWeight.w700));
  }
}

class _GroupNameEditor extends StatelessWidget {
  const _GroupNameEditor({
    required this.group,
    required this.controller,
    required this.isEditing,
    required this.onStartEditing,
    required this.onCancel,
    required this.onSave,
  });

  final GroupListItemData group;
  final TextEditingController controller;
  final bool isEditing;
  final VoidCallback onStartEditing;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    if (!isEditing) {
      return Row(
        children: [
          Expanded(
            child: Text(
              group.name,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w800),
            ),
          ),
          IconButton(
            tooltip: '모임 이름 수정',
            onPressed: onStartEditing,
            icon: const Icon(Icons.edit_outlined, size: 19),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 30,
            inputFormatters: [LengthLimitingTextInputFormatter(30)],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSave(),
            decoration: const InputDecoration(counterText: '', isDense: true),
          ),
        ),
        TextButton(onPressed: onSave, child: const Text('저장')),
        IconButton(
          tooltip: '수정 취소',
          onPressed: onCancel,
          icon: const Icon(Icons.close, size: 19),
        ),
      ],
    );
  }
}

class _PinColorButton extends StatelessWidget {
  const _PinColorButton({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: isSelected,
      label: '핀 색상',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? AppColors.ink : Colors.transparent,
              width: 3,
            ),
          ),
          child: isSelected
              ? const Icon(Icons.check, color: Colors.white, size: 19)
              : null,
        ),
      ),
    );
  }
}
