import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/network/api_transport.dart';
import '../services/group_api_service.dart';
import '../services/group_list_store.dart';

class JoinGroupScreen extends StatefulWidget {
  const JoinGroupScreen({super.key, required this.inviteCode});

  final String inviteCode;

  @override
  State<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> {
  GroupApiItem? _joinedGroup;
  bool _isJoining = false;

  Future<void> _joinGroup() async {
    setState(() => _isJoining = true);
    try {
      final group = await GroupApiService.joinGroup(widget.inviteCode);
      GroupListStore.upsertGroup(group);
      if (!mounted) return;
      setState(() => _joinedGroup = group);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${group.displayName ?? group.name}에 참여했어요.')),
      );
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _isJoining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('모임 초대')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          children: [
            if (_joinedGroup case final group?)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        radius: 22,
                        backgroundColor: AppColors.softMint,
                        child: Icon(
                          Icons.groups_outlined,
                          color: AppColors.deepNavy,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              group.name,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            Text('멤버 ${group.memberCount}명'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_joinedGroup != null) const SizedBox(height: AppSpacing.lg),
            Text(
              _joinedGroup == null ? '초대 코드로\n모임에 참여할까요?' : '모임에 참여했어요.',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontSize: 27, height: 1.25),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              _joinedGroup == null
                  ? '초대 코드를 확인하고 참여하면 모임 멤버와 기록을 공유할 수 있어요.'
                  : '이제 모임 멤버와 장소 기록을 공유할 수 있어요.',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(height: 1.65),
            ),
            const SizedBox(height: AppSpacing.lg),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '초대 정보',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: AppColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '공유된 초대 코드로 확인했습니다.',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(fontSize: 12),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: const BoxDecoration(
                        color: AppColors.paleMint,
                        borderRadius: BorderRadius.all(
                          Radius.circular(AppSpacing.xs),
                        ),
                      ),
                      child: Text(
                        '초대 코드: ${widget.inviteCode}',
                        style: const TextStyle(
                          color: AppColors.deepNavy,
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_joinedGroup == null) ...[
              ElevatedButton(
                onPressed: _isJoining ? null : _joinGroup,
                child: _isJoining
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('코드로 모임 참여하기'),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '참여 후에는 모임 멤버에게만 기록이 공유됩니다.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(height: 1.65),
              ),
            ] else ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '참여가 완료됐어요.',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: AppColors.ink,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '이제 모임의 장소 기록과 피드를 볼 수 있어요.',
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(height: 1.55),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('모임 목록으로 돌아가기'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
