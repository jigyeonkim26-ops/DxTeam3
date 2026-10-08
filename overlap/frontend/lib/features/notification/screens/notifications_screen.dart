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
          const SizedBox(height: AppSpacing.sm),
          if (MockNotificationRepository.items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(
                child: Text(
                  '새로운 알림이 없어요.',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            ),
          ...MockNotificationRepository.items.map(
            (item) => NotificationListItem(
              item: item,
              onTap: () => ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(_message(item.type)))),
            ),
          ),
        ],
      ),
    ),
  );
}
