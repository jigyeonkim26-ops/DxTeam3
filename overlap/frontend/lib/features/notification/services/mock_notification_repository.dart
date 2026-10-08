import '../models/notification_item_data.dart';

/// Notifications are shown only when supplied by the API.
abstract final class MockNotificationRepository {
  static const List<NotificationItemData> items = [];
}
