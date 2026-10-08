import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/network/api_transport.dart';
import '../models/group_visibility.dart';
import '../services/group_api_service.dart';
import '../widgets/invite_info_card.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();

  GroupVisibility _visibility = GroupVisibility.invitedMembersOnly;
  GroupApiCreated? _invite;
  bool _isCreating = false;

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
    setState(() => _isCreating = true);
    try {
      final created = await GroupApiService.createGroup(
        name: _nameController.text.trim(),
        description: _descriptionController.text,
        visibility: _visibility.apiValue,
      );
      if (!mounted) return;
      setState(() => _invite = created);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('${created.name} 모임을 만들었어요.')));
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  void _copyInviteValue(String value, String label) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$label 복사했어요.')));
  }

  @override
  Widget build(BuildContext context) {
    final invite = _invite;

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
              const SizedBox(height: AppSpacing.md),
              Text('공유 범위', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              DropdownButtonFormField<GroupVisibility>(
                initialValue: _visibility,
                isExpanded: true,
                decoration: const InputDecoration(),
                items: GroupVisibility.values
                    .map(
                      (visibility) => DropdownMenuItem(
                        value: visibility,
                        child: Text(visibility.label),
                      ),
                    )
                    .toList(),
                onChanged: (visibility) {
                  if (visibility != null) {
                    setState(() => _visibility = visibility);
                  }
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              ElevatedButton(
                onPressed: _isCreating ? null : _createGroup,
                child: _isCreating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('모임 만들기'),
              ),
              if (invite != null) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Divider(),
                ),
                Text(
                  '${_nameController.text.trim()} 초대',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '초대 링크를 공유하면, 친구는 링크를 열어 참여 여부를 확인할 수 있어요.',
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(height: 1.65),
                ),
                const SizedBox(height: AppSpacing.sm),
                InviteInfoCard(
                  title: '초대 코드',
                  description: '짧은 코드를 직접 전달할 때 사용하세요.',
                  value: invite.inviteCode,
                  copyLabel: '코드 복사',
                  onCopy: () => _copyInviteValue(invite.inviteCode, '초대 코드'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
