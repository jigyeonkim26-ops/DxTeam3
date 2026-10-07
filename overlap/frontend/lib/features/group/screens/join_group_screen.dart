import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../models/group_invite_preview.dart';
import '../services/mock_group_join_service.dart';
import '../widgets/group_invite_summary_card.dart';

class JoinGroupScreen extends StatefulWidget {
  const JoinGroupScreen({super.key, required this.inviteCode});

  final String inviteCode;

  @override
  State<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> {
  late final GroupInvitePreview _preview;
  bool _hasJoined = false;

  @override
  void initState() {
    super.initState();
    _preview = MockGroupJoinService.previewForCode(widget.inviteCode);
  }

  void _joinGroup() {
    setState(() => _hasJoined = true);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('${_preview.groupName}에 참여했어요.')));
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
            GroupInviteSummaryCard(preview: _preview),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '${_preview.ownerName}님이 모임에\n초대했습니다.',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontSize: 27, height: 1.25),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '참여하면 ${_preview.groupName}의 장소 기록을 보고, 나의 순간도 함께 남길 수 있어요.',
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
                        '초대 코드: ${_preview.inviteCode}',
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
            if (!_hasJoined) ...[
              ElevatedButton(
                onPressed: _joinGroup,
                child: Text('${_preview.groupName}에 참여하기'),
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
                        onPressed: () => Navigator.pop(context),
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
