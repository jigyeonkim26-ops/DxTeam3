import '../models/notification_settings_data.dart';

abstract final class MockNotificationSettingsRepository {
  static const initial = NotificationSettingsData(
    commentsAndRepliesEnabled: true,
    reactionsEnabled: true,
    newGroupRecordsEnabled: true,
    groupUpdatesEnabled: true,
    nearbyReminderEnabled: false,
    quietStartTime: '22:00',
    quietEndTime: '08:00',
  );
}
