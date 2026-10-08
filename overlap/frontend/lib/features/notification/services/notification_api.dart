import 'package:flutter/foundation.dart';

import '../../../core/network/api_transport.dart';
import '../../../core/network/api_client.dart' show ApiClient;
import '../models/notification_item_data.dart';
import '../models/notification_settings_data.dart';

abstract final class NotificationApi {
  static final unreadCount = _createUnreadCount();
  static ValueNotifier<int> _createUnreadCount() {
    final notifier = ValueNotifier<int>(0);
    ApiClient.sessionRevision.addListener(() => notifier.value = 0);
    return notifier;
  }

  static Future<void> refreshUnreadCount() async {
    final token = ApiTransport.accessToken;
    if (token == null) {
      unreadCount.value = 0;
      return;
    }
    final response =
        await ApiTransport.get('/notifications/unread-count') as Map;
    if (token != ApiTransport.accessToken) return;
    unreadCount.value = response['unread_count'] as int;
  }

  static Future<List<NotificationItemData>> load() async {
    final items = <NotificationItemData>[];
    var offset = 0;
    while (true) {
      final page = await ApiTransport.get(
        '/notifications?limit=100&offset=$offset',
      ) as Map;
      final batch = (page['items'] as List)
          .map(
            (item) => NotificationItemData.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
      items.addAll(batch);
      offset += batch.length;
      if (batch.isEmpty || offset >= (page['total'] as int)) return items;
    }
  }

  static Future<void> read(int id) async {
    await ApiTransport.patch('/notifications/$id/read');
    await refreshUnreadCount();
  }

  static Future<void> readAll() async {
    final response = await ApiTransport.patch('/notifications/read-all') as Map;
    unreadCount.value = response['unread_count'] as int;
  }

  static Future<NotificationSettingsData> settings() async =>
      NotificationSettingsData.fromJson(
        Map<String, dynamic>.from(
          await ApiTransport.get('/notifications/settings') as Map,
        ),
      );
  static Future<NotificationSettingsData> saveSettings(
    NotificationSettingsData settings,
  ) async => NotificationSettingsData.fromJson(
    Map<String, dynamic>.from(
      await ApiTransport.patch(
        '/notifications/settings',
        body: settings.toJson(),
      ) as Map,
    ),
  );
}
