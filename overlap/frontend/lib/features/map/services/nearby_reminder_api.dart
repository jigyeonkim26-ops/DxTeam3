import '../../../core/network/api_transport.dart';
import '../models/current_location.dart';
import '../models/nearby_reminder.dart';

abstract interface class NearbyReminderService {
  Future<List<NearbyReminder>> check(CurrentLocation location);
}

class NearbyReminderApi implements NearbyReminderService {
  @override
  Future<List<NearbyReminder>> check(CurrentLocation location) async {
    final response = await ApiTransport.post(
      '/reminders/nearby',
      body: {'latitude': location.latitude, 'longitude': location.longitude},
    ) as Map;
    final items = response['items'];
    if (items is! List) {
      throw const ApiException('근처 기록 응답을 읽을 수 없습니다.');
    }
    return items
        .whereType<Map>()
        .map((item) => NearbyReminder.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }
}
