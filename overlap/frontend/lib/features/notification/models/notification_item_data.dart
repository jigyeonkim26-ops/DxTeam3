enum NotificationType { newRecord, comment, placeUpdate, groupInvite }

class NotificationItemData {
  const NotificationItemData({
    required this.type,
    required this.title,
    required this.description,
    required this.timeText,
    required this.isRead,
  });
  final NotificationType type;
  final String title;
  final String description;
  final String timeText;
  final bool isRead;
}
