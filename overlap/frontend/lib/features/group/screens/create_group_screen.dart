import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/group.dart';

typedef CreateGroupCallback = Future<Group?> Function({
  required String name,
  required String description,
});

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key, this.onCreateGroup});

  final CreateGroupCallback? onCreateGroup;

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    FocusScope.of(context).unfocus();
    final createGroup = widget.onCreateGroup;
    if (createGroup == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('모임 생성은 서버 연결 후 사용할 수 있어요.')),
      );
      return;
    }

    final group = await createGroup(
      name: _nameController.text.trim(),
      description: _descriptionController.text.trim(),
    );
    if (!mounted || group == null) return;
    await _showGroupCreatedSheet(group.inviteCode);
  }

  Future<void> _copyInviteCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('초대 코드가 복사되었어요.')));
  }

  Future<void> _showGroupCreatedSheet(String? inviteCode) async {
    final hasInviteCode = inviteCode?.trim().isNotEmpty ?? false;
    final isComplete = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '모임이 만들어졌어요!',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppColors.ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '초대 코드를 친구에게 보내\n모임에 함께 참여해 보세요.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppColors.muted, height: 1.55),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text(
                '초대 코드',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.xs),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.paleMint,
                  borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                ),
                child: Text(
                  hasInviteCode ? inviteCode!.trim() : '초대 코드를 불러오지 못했어요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: hasInviteCode ? AppColors.deepNavy : AppColors.muted,
                    fontSize: hasInviteCode ? 22 : 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: hasInviteCode ? 1.4 : 0,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ElevatedButton.icon(
                onPressed: hasInviteCode
                    ? () => _copyInviteCode(inviteCode!.trim())
                    : null,
                icon: const Icon(Icons.copy_outlined),
                label: const Text('초대코드 복사'),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextButton(
                onPressed: () => Navigator.of(sheetContext).pop(true),
                child: const Text('완료'),
              ),
            ],
          ),
        ),
      ),
    );
    if (isComplete == true && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('새 모임 만들기')),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            children: [
              Text(
                '새 모임을\n만들어볼까요?',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontSize: 27, height: 1.25),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '같이 장소를 기록할 친구들을 초대해 보세요.\n모임 기록은 참여한 멤버만 볼 수 있어요.',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(height: 1.65),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('모임 이름', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              TextFormField(
                controller: _nameController,
                maxLength: 30,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(counterText: ''),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '모임 이름을 입력해 주세요.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              Text('모임 소개', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              TextFormField(
                controller: _descriptionController,
                minLines: 3,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(alignLabelWithHint: true),
              ),
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                onPressed: _createGroup,
                child: const Text('모임 만들기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
