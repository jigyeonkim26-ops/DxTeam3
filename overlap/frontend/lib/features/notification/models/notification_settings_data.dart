class NotificationSettingsData {
  const NotificationSettingsData({
    required this.commentsAndRepliesEnabled,
    required this.reactionsEnabled,
    required this.newGroupRecordsEnabled,
    required this.groupUpdatesEnabled,
    required this.nearbyReminderEnabled,
    required this.quietStartTime,
    required this.quietEndTime,
  });
  final bool commentsAndRepliesEnabled,
      reactionsEnabled,
      newGroupRecordsEnabled,
      groupUpdatesEnabled,
      nearbyReminderEnabled;
  final String quietStartTime, quietEndTime;
  factory NotificationSettingsData.fromJson(Map<String, dynamic> json) =>
      NotificationSettingsData(
        commentsAndRepliesEnabled: json['comments_replies_enabled'] as bool,
        reactionsEnabled: json['reactions_enabled'] as bool,
        newGroupRecordsEnabled: json['new_group_records_enabled'] as bool,
        groupUpdatesEnabled: json['group_updates_enabled'] as bool,
        nearbyReminderEnabled: json['nearby_reminder_enabled'] as bool,
        quietStartTime: json['quiet_start_time'] as String? ?? '',
        quietEndTime: json['quiet_end_time'] as String? ?? '',
      );
  Map<String, dynamic> toJson() => {
    'comments_replies_enabled': commentsAndRepliesEnabled,
    'reactions_enabled': reactionsEnabled,
    'new_group_records_enabled': newGroupRecordsEnabled,
    'group_updates_enabled': groupUpdatesEnabled,
    'nearby_reminder_enabled': nearbyReminderEnabled,
    'quiet_start_time': quietStartTime.isEmpty ? null : quietStartTime,
    'quiet_end_time': quietEndTime.isEmpty ? null : quietEndTime,
  };
  NotificationSettingsData copyWith({
    bool? commentsAndRepliesEnabled,
    bool? reactionsEnabled,
    bool? newGroupRecordsEnabled,
    bool? groupUpdatesEnabled,
    bool? nearbyReminderEnabled,
    String? quietStartTime,
    String? quietEndTime,
  }) => NotificationSettingsData(
    commentsAndRepliesEnabled:
        commentsAndRepliesEnabled ?? this.commentsAndRepliesEnabled,
    reactionsEnabled: reactionsEnabled ?? this.reactionsEnabled,
    newGroupRecordsEnabled:
        newGroupRecordsEnabled ?? this.newGroupRecordsEnabled,
    groupUpdatesEnabled: groupUpdatesEnabled ?? this.groupUpdatesEnabled,
    nearbyReminderEnabled: nearbyReminderEnabled ?? this.nearbyReminderEnabled,
    quietStartTime: quietStartTime ?? this.quietStartTime,
    quietEndTime: quietEndTime ?? this.quietEndTime,
  );
}
