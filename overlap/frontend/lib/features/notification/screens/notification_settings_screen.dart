import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../models/notification_settings_data.dart';
import '../services/mock_notification_settings_repository.dart';
import '../widgets/notification_setting_tile.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});
  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  late NotificationSettingsData _settings;
  @override
  void initState() {
    super.initState();
    _settings = MockNotificationSettingsRepository.initial;
  }

  void _change(NotificationSettingsData value, {String? message}) {
    setState(() => _settings = value);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message ?? '알림 설정을 저장했어요.')));
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('NOTIFICATION SETTINGS')),
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
          Text(
            '알림 설정',
            style: Theme.of(c).textTheme.headlineSmall?.copyWith(fontSize: 27),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '원하는 소식만 받을 수 있도록 유형별로 조절하세요.',
            style: Theme.of(c).textTheme.bodyMedium?.copyWith(height: 1.65),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => Navigator.pop(c),
                  child: const _Tab('알림함', false),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              const Expanded(child: _Tab('알림 설정', true)),
            ],
          ),
          _Group(
            title: '기록 활동',
            description: '내 기록과 이어진 대화, 내가 참여하는 모임의 새 기록입니다.',
            children: [
              NotificationSettingTile(
                title: '댓글과 답글',
                description: '내 기록에 댓글이 달리거나 답글이 이어질 때',
                value: _settings.commentsAndRepliesEnabled,
                onChanged: (v) =>
                    _change(_settings.copyWith(commentsAndRepliesEnabled: v)),
              ),
              NotificationSettingTile(
                title: '공감과 이어쓰기',
                description: '내 기록에 공감하거나 새 기록이 이어질 때',
                value: _settings.reactionsEnabled,
                onChanged: (v) =>
                    _change(_settings.copyWith(reactionsEnabled: v)),
              ),
              NotificationSettingTile(
                title: '모임의 새 기록',
                description: '참여 중인 모임에 새 장소 기록이 올라올 때',
                value: _settings.newGroupRecordsEnabled,
                onChanged: (v) =>
                    _change(_settings.copyWith(newGroupRecordsEnabled: v)),
              ),
            ],
          ),
          _Group(
            title: '모임 소식',
            children: [
              NotificationSettingTile(
                title: '모임 초대와 멤버 변경',
                description: '새 초대, 가입 승인, 멤버 변경 소식',
                value: _settings.groupUpdatesEnabled,
                onChanged: (v) =>
                    _change(_settings.copyWith(groupUpdatesEnabled: v)),
              ),
            ],
          ),
          _Group(
            title: '장소 근처 리마인드',
            description: '저장한 장소 근처에 도착했을 때, 과거 기록을 다시 볼 수 있도록 알려줘요.',
            children: [
              NotificationSettingTile(
                title: '장소 근처 알림',
                description: '선택한 장소 반경 안에 들어왔을 때만 알림',
                value: _settings.nearbyReminderEnabled,
                onChanged: (v) => _change(
                  _settings.copyWith(nearbyReminderEnabled: v),
                  message: v ? '위치 권한 연동은 추후 적용됩니다.' : '장소 근처 리마인드를 해제했어요.',
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  '실제 앱에서는 별도의 위치 권한 동의가 필요합니다. 목업에서는 설정 상태만 변경합니다.',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    height: 1.55,
                  ),
                ),
              ),
            ],
          ),
          _Group(
            title: '방해 금지 시간',
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _settings.quietStartTime,
                      items: ['22:00', '23:00']
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          _change(_settings.copyWith(quietStartTime: v));
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _settings.quietEndTime,
                      items: ['08:00', '09:00']
                          .map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          _change(_settings.copyWith(quietEndTime: v));
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _Tab extends StatelessWidget {
  const _Tab(this.label, this.active);
  final String label;
  final bool active;
  @override
  Widget build(BuildContext c) => Container(
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(vertical: 10),
    decoration: BoxDecoration(
      color: active ? AppColors.deepNavy : AppColors.paleMint,
      borderRadius: const BorderRadius.all(Radius.circular(10)),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: active ? Colors.white : AppColors.deepNavy,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    this.description,
    this.children = const [],
  });
  final String title;
  final String? description;
  final List<Widget> children;
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(c).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (description != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            description!,
            style: Theme.of(c).textTheme.bodyMedium
                ?.copyWith(fontSize: 11, height: 1.5),
          ),
        ],
        ...children,
      ],
    ),
  );
}
