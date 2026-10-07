import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../models/notification_item_data.dart';
import '../services/mock_notification_repository.dart';
import '../widgets/notification_list_item.dart';
import 'notification_settings_screen.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});
  void _settings(BuildContext c) => Navigator.of(c).push(
    MaterialPageRoute<void>(builder: (_) => const NotificationSettingsScreen()),
  );
  String _message(NotificationType t) => switch (t) {
    NotificationType.newRecord ||
    NotificationType.comment => '기록 상세 연결은 추후 적용됩니다.',
    NotificationType.placeUpdate => '장소 상세 연결은 추후 적용됩니다.',
    NotificationType.groupInvite => '모임 연결은 추후 적용됩니다.',
  };
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      centerTitle: true,
      title: const Text(
        '실시간 알림',
        style: TextStyle(
          color: AppColors.deepNavy,
          fontWeight: FontWeight.w700,
        ),
      ),
      actions: [
        IconButton(
          onPressed: () => _settings(context),
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    ),
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
            '내 모임에서 일어난 기록 활동을 모아 보여줘요.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(height: 1.65),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              const Expanded(child: _Tab(label: '알림함', active: true)),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: InkWell(
                  onTap: () => _settings(context),
                  child: const _Tab(label: '알림 설정', active: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ...MockNotificationRepository.items.map(
            (item) => NotificationListItem(
              item: item,
              onTap: () => ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(_message(item.type)))),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton(
            onPressed: () => ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('샘플 알림을 보냈어요.'))),
            child: const Text('샘플 알림 보내기'),
          ),
        ],
      ),
    ),
  );
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.active});
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
