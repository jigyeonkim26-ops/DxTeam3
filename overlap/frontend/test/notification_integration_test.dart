import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overlap_app/core/network/api_client.dart';
import 'package:overlap_app/features/notification/services/notification_api.dart';
import 'package:overlap_app/features/notification/screens/notifications_screen.dart';
import 'package:overlap_app/features/notification/screens/notification_settings_screen.dart';
import 'package:overlap_app/features/notification/widgets/notification_list_item.dart';
import 'package:overlap_app/features/notification/widgets/notification_setting_tile.dart';
import 'package:overlap_app/features/ai/screens/ai_recommendation_screen.dart';

Map<String, Object?> notification(int id, {bool read = false}) => {
  'id': id,
  'type': 'LIKE',
  'title': 'Actual notification $id',
  'message': 'Actual message',
  'reference_type': 'RECORD',
  'reference_id': 99,
  'is_read': read,
  'created_at': '2026-10-08T01:00:00',
};
Map<String, Object?> settings() => {
  'comments_replies_enabled': true,
  'reactions_enabled': true,
  'new_group_records_enabled': true,
  'group_updates_enabled': true,
  'nearby_reminder_enabled': false,
  'quiet_start_time': null,
  'quiet_end_time': '08:30:00',
};
void main() {
  setUp(() => ApiClient.setAccessToken('notification-test-token'));
  tearDown(ApiClient.clearSession);
  test('loads all latest-first pages with the current login token and handles real types', () async {
    final server = _Client((request) {
      expect(
        request.headers.values['authorization'],
        'Bearer notification-test-token',
      );
      final offset = int.parse(request.uri.queryParameters['offset']!);
      return {
        'items': [notification(offset == 0 ? 2 : 1)],
        'total': 2,
        'offset': offset,
        'limit': 100,
      };
    });
    await HttpOverrides.runZoned(() async {
      final items = await NotificationApi.load();
      expect(items.map((n) => n.id), [2, 1]);
      expect(items.first.referenceId, 99);
      expect(items.first.isRead, false);
    }, createHttpClient: (_) => server);
  });
  test(
    'single and all read use PATCH and update unread count; logout clears it',
    () async {
      final server = _Client(
        (request) => request.uri.path.endsWith('unread-count')
            ? {'unread_count': 1}
            : request.uri.path.endsWith('read-all')
            ? {'unread_count': 0}
            : notification(2, read: true),
      );
      await HttpOverrides.runZoned(() async {
        await NotificationApi.read(2);
        expect(NotificationApi.unreadCount.value, 1);
        expect(server.requests.first.method, 'PATCH');
        expect(server.requests.first.uri.path, '/notifications/2/read');
        await NotificationApi.readAll();
        expect(NotificationApi.unreadCount.value, 0);
        NotificationApi.unreadCount.value = 3;
        ApiClient.clearSession();
        expect(NotificationApi.unreadCount.value, 0);
      }, createHttpClient: (_) => server);
    },
  );
  test('settings persist nullable and minute-specific quiet hours', () async {
    final server = _Client(
      (request) => request.method == 'PATCH'
          ? jsonDecode(request.body.toString())
          : settings(),
    );
    await HttpOverrides.runZoned(() async {
      final current = await NotificationApi.settings();
      expect(current.quietStartTime, '');
      expect(current.quietEndTime, '08:30:00');
      final saved = await NotificationApi.saveSettings(
        current.copyWith(reactionsEnabled: false),
      );
      expect(saved.reactionsEnabled, false);
      expect(
        jsonDecode(server.requests.last.body.toString())['quiet_start_time'],
        isNull,
      );
    }, createHttpClient: (_) => server);
  });
  testWidgets(
    'zero notifications displays empty state and removes sample button',
    (tester) async {
      final server = _Client(
        (request) => request.uri.path.endsWith('unread-count')
            ? {'unread_count': 0}
            : {'items': [], 'total': 0, 'offset': 0, 'limit': 100},
      );
      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(const MaterialApp(home: NotificationsScreen()));
        await tester.pumpAndSettle();
        expect(find.text('아직 알림이 없어요.'), findsOneWidget);
        expect(find.text('샘플 알림 보내기'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }, createHttpClient: (_) => server);
    },
  );
  testWidgets(
    'deleted or inaccessible referenced record stays on notifications',
    (tester) async {
      final server = _Client((request) {
        if (request.uri.path == '/feed') return {'items': [], 'total': 0};
        if (request.uri.path.endsWith('unread-count')) {
          return {'unread_count': 0};
        }
        if (request.method == 'PATCH') return notification(2, read: true);
        return {
          'items': [notification(2)],
          'total': 1,
        };
      });
      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(const MaterialApp(home: NotificationsScreen()));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(NotificationListItem));
        await tester.pumpAndSettle();
        expect(find.text('삭제되었거나 접근할 수 없는 기록이에요.'), findsOneWidget);
        expect(find.byType(NotificationsScreen), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      }, createHttpClient: (_) => server);
    },
  );
  testWidgets('failed settings save preserves last server value', (
    tester,
  ) async {
    final server = _Client((request) => settings());
    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(
        const MaterialApp(home: NotificationSettingsScreen()),
      );
      await tester.pumpAndSettle();
      server.status = 500;
      final toggle = tester.widget<NotificationSettingTile>(
        find.byType(NotificationSettingTile).first,
      );
      toggle.onChanged(false);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<NotificationSettingTile>(
              find.byType(NotificationSettingTile).first,
            )
            .value,
        true,
      );
      expect(find.text('저장하지 못했어요. 다시 시도해 주세요.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }, createHttpClient: (_) => server);
  });
  testWidgets(
    'AI displays empty results without mock recommendations or analysis',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: AiRecommendationScreen()),
      );
      expect(find.text('아직 추천 장소가 없어요.'), findsOneWidget);
      expect(find.text('다른 장소 추천받기'), findsNothing);
      expect(find.text('최근 기록을\n분석했어요'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

class _Client implements HttpClient {
  _Client(this.respond);
  final Object? Function(_Request request) respond;
  int status = 200;
  final requests = <_Request>[];
  @override
  Duration? connectionTimeout;
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    final request = _Request(method, url, this);
    requests.add(request);
    return request;
  }

  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

class _Request implements HttpClientRequest {
  _Request(this.method, this.uri, this.client);
  @override
  final String method;
  @override
  final Uri uri;
  final _Client client;
  final body = StringBuffer();
  @override
  final _Headers headers = _Headers();
  @override
  void write(Object? object) => body.write(object);
  @override
  Future<HttpClientResponse> close() async =>
      _Response(client.respond(this), client.status);
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

class _Headers implements HttpHeaders {
  final values = <String, Object>{};
  @override
  ContentType? contentType;
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}

class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response(Object? data, this.statusCode)
    : _stream = Stream.value(data == null ? [] : utf8.encode(jsonEncode(data)));
  final Stream<List<int>> _stream;
  @override
  final int statusCode;
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName}');
}
