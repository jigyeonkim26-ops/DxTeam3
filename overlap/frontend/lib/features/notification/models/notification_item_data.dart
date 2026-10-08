enum NotificationType {
  newRecord,
  comment,
  placeUpdate,
  groupInvite,
  reaction,
  other,
}

class NotificationItemData {
  const NotificationItemData({
    this.id = 0,
    this.referenceType,
    this.referenceId,
    required this.type,
    required this.title,
    required this.description,
    required this.timeText,
    required this.isRead,
  });
  final int id;
  final String? referenceType;
  final int? referenceId;
  factory NotificationItemData.fromJson(Map<String, dynamic> json) {
    final rawTime = json['created_at'] as String;
    final timestamp = DateTime.parse(
      RegExp(r'(Z|[+-]\d\d:\d\d)$').hasMatch(rawTime) ? rawTime : '${rawTime}Z',
    );
    return NotificationItemData(
      id: json['id'] as int,
      referenceType: json['reference_type'] as String?,
      referenceId: json['reference_id'] as int?,
      type: switch (json['type']) {
        'GROUP_RECORD' => NotificationType.newRecord,
        'COMMENT' || 'REPLY' => NotificationType.comment,
        'LIKE' => NotificationType.reaction,
        'GROUP_UPDATE' => NotificationType.groupInvite,
        _ => NotificationType.other,
      },
      title: json['title'] as String,
      description: json['message'] as String,
      timeText: timestamp.toLocal().toString().substring(0, 16),
      isRead: json['is_read'] as bool,
    );
  }
  final NotificationType type;
  final String title;
  final String description;
  final String timeText;
  final bool isRead;
}
