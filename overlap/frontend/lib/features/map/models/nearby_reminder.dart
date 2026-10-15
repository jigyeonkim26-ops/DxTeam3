import '../../../shared/models/record.dart';

class NearbyReminder {
  const NearbyReminder({
    required this.record,
    required this.distanceMeters,
    required this.notificationId,
    required this.notificationCreated,
  });

  final Record record;
  final int distanceMeters;
  final int notificationId;
  final bool notificationCreated;

  factory NearbyReminder.fromJson(Map<String, dynamic> json) => NearbyReminder(
    record: Record.fromJson(Map<String, dynamic>.from(json['record'] as Map)),
    distanceMeters: (json['distance_meters'] as num).round(),
    notificationId: json['notification_id'] as int,
    notificationCreated: json['notification_created'] as bool,
  );
}
