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
