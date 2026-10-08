import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:overlap_app/core/network/api_client.dart';
import 'package:overlap_app/core/network/api_transport.dart';
import 'package:overlap_app/features/auth/services/auth_api_service.dart';
import 'package:overlap_app/features/group/screens/groups_screen.dart';
import 'package:overlap_app/features/group/services/group_api_service.dart';
import 'package:overlap_app/features/group/services/group_list_store.dart';
import 'package:overlap_app/features/memory/services/record_api.dart';

Map<String, Object?> groupResponse() => {
  'id': 10,
  'name': '실제 서버 모임',
  'member_count': 3,
  'description': '서버 소개',
  'visibility': 'INVITED_ONLY',
  'notifications_enabled': true,
  'pin_color_value': 0xFF6FAE8F,
};

void main() {
  tearDown(() {
    ApiClient.clearSession();
    GroupListStore.clear();
  });

  test(
    'Ujin login and RecordApi share one token; logout clears group cache',
    () async {
      final server = _Client((request) => {'access_token': 'ujin-test-token'});
      await HttpOverrides.runZoned(() async {
        await AuthApiService.login(
          email: 'test@example.com',
          password: 'test-password',
        );
      }, createHttpClient: (_) => server);
      expect(ApiClient.accessToken, 'ujin-test-token');
      final api = RecordApi(
        client: MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer ujin-test-token');
          return http.Response('[]', 200);
        }),
      );
      await api.groups();
      api.close();
      final client = _Client((request) => [groupResponse()]);
      await HttpOverrides.runZoned(
        GroupListStore.refreshGroups,
        createHttpClient: (_) => client,
      );
      expect(
        client.requests.single.headers.values['authorization'],
        'Bearer ujin-test-token',
      );
      expect(GroupListStore.groups.single.name, '실제 서버 모임');
      ApiClient.clearSession();
      expect(ApiTransport.accessToken, isNull);
      expect(GroupListStore.groups, isEmpty);
      ApiClient.setAccessToken('next-account-token');
      expect(ApiTransport.accessToken, 'next-account-token');
      ApiTransport.clearAccessToken();
      expect(ApiClient.accessToken, isNull);
    },
  );

  test('create, join, and leave update the shared group cache immediately', () {
    GroupListStore.upsertGroup(
      const GroupApiItem(id: 10, name: 'Created group', memberCount: 1),
      inviteCode: 'CREATED-CODE',
    );
    expect(GroupListStore.groups.single.name, 'Created group');
    expect(GroupListStore.groups.single.inviteCode, 'CREATED-CODE');

    GroupListStore.upsertGroup(
      const GroupApiItem(id: 11, name: 'Joined group', memberCount: 2),
    );
    expect(GroupListStore.groups.map((group) => group.id), ['10', '11']);

    expect(GroupListStore.removeGroupFromCache('10'), isTrue);
    expect(GroupListStore.groups.map((group) => group.id), ['11']);
  });

  test(
    'malformed member entries are reported as an API error, not an empty group',
    () async {
      ApiTransport.setAccessToken('group-test-token');
      final server = _Client(
        (_) => [
          {'id': 10, 'nickname': '서연', 'is_current_user': true},
          {'id': 'invalid', 'nickname': '잘못된 응답'},
        ],
      );
      await HttpOverrides.runZoned(() async {
        await expectLater(
          GroupApiService.getGroupMembers(10),
          throwsA(isA<ApiException>()),
        );
      }, createHttpClient: (_) => server);
    },
  );

  test(
    'an authenticated 401 clears a session once, but login 401 does not',
    () async {
      ApiTransport.setAccessToken('expired-token');
      var sessionChanges = 0;
      void onSessionChanged() => sessionChanges++;
      ApiClient.sessionRevision.addListener(onSessionChanged);
      addTearDown(
        () => ApiClient.sessionRevision.removeListener(onSessionChanged),
      );

      final server = _Client((_) => {'detail': 'expired'}, status: 401);
      await HttpOverrides.runZoned(() async {
        await expectLater(
          ApiTransport.get('/protected'),
          throwsA(
            isA<ApiException>().having(
              (error) => error.statusCode,
              'statusCode',
              401,
            ),
          ),
        );
        await expectLater(
          ApiTransport.get('/protected'),
          throwsA(isA<ApiException>()),
        );
      }, createHttpClient: (_) => server);

      expect(ApiClient.accessToken, isNull);
      expect(ApiClient.sessionExpired, isTrue);
      expect(sessionChanges, 1);

      final revisionAfterExpiry = ApiClient.sessionRevision.value;
      await HttpOverrides.runZoned(() async {
        await expectLater(
          AuthApiService.login(email: 'user@example.com', password: 'wrong'),
          throwsA(isA<ApiException>()),
        );
      }, createHttpClient: (_) => server);
      expect(ApiClient.sessionRevision.value, revisionAfterExpiry);
    },
  );

  test('actual group requests preserve contracts and settings without sample members', () async {
    ApiTransport.setAccessToken('group-test-token');
    final server = _Client((request) {
      if (request.uri.path == '/groups' && request.method == 'GET') {
        return [groupResponse()];
      }
      if (request.uri.path == '/groups/10/members') {
        return [
          {'id': 10, 'nickname': '서연', 'is_current_user': true},
          {'id': 11, 'nickname': '지연', 'is_current_user': false},
        ];
      }
      if (request.uri.path.endsWith('/invite')) {
        return {'invite_code': 'REAL-CODE'};
      }
      if (request.method == 'DELETE') return null;
      return {...groupResponse(), 'invite_code': 'REAL-CODE'};
    });
    await HttpOverrides.runZoned(() async {
      await GroupListStore.refreshGroups();
      final group = GroupListStore.groups.single;
      expect(group.members, isEmpty);
      expect(group.memberCount, 3);
      expect(group.description, '서버 소개');
      final renamed = group.copyWith(
        name: '내 별칭',
        visibility: 'LINK_REQUEST_ALLOWED',
      );
      expect(renamed.members, isEmpty);
      expect(renamed.description, '서버 소개');
      expect(renamed.visibility, 'LINK_REQUEST_ALLOWED');
      final members = await GroupApiService.getGroupMembers(10);
      expect(members.map((member) => member.nickname), ['서연', '지연']);
      expect(members.singleWhere((member) => member.isCurrentUser).id, '10');
      expect(server.requests.last.uri.path, '/groups/10/members');
      await GroupApiService.updatePreferences(
        id: 10,
        updateCustomName: true,
        customName: '내 별칭',
        notificationsEnabled: false,
        pinColorValue: 0xFF14364A,
      );
      expect(jsonDecode(server.requests.last.body.toString()), {
        'custom_name': '내 별칭',
        'notifications_enabled': false,
        'pin_color_value': 0xFF14364A,
      });
      expect(server.requests.last.method, 'PATCH');
      expect(server.requests.last.uri.path, '/groups/10/preferences');
      await GroupApiService.updateGroupDetails(
        id: 10,
        description: '새 소개',
        visibility: 'LINK_REQUEST_ALLOWED',
      );
      expect(server.requests.last.method, 'PUT');
      expect(jsonDecode(server.requests.last.body.toString()), {
        'description': '새 소개',
        'visibility': 'LINK_REQUEST_ALLOWED',
      });
      expect(await GroupApiService.getInviteCode(10), 'REAL-CODE');
      await GroupApiService.createGroup(
        name: ' 새 모임 ',
        description: ' 소개 ',
        visibility: 'INVITED_ONLY',
      );
      expect(jsonDecode(server.requests.last.body.toString()), {
        'name': '새 모임',
        'description': '소개',
        'visibility': 'INVITED_ONLY',
      });
      await GroupApiService.joinGroup(' REAL-CODE ');
      expect(server.requests.last.uri.path, '/groups/join');
      expect(jsonDecode(server.requests.last.body.toString()), {
        'invite_code': 'REAL-CODE',
      });
      await GroupApiService.leaveGroup(10);
      expect(server.requests.last.method, 'DELETE');
      expect(server.requests.last.uri.path, '/groups/10/members/me');
    }, createHttpClient: (_) => server);
    expect(
      server.requests.every(
        (request) =>
            request.headers.values['authorization'] ==
            'Bearer group-test-token',
      ),
      isTrue,
    );
  });

  testWidgets('server group opens management UI with actual member details', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    ApiTransport.setAccessToken('group-test-token');
    final server = _Client((request) {
      if (request.uri.path == '/groups' && request.method == 'GET') {
        return [groupResponse()];
      }
      if (request.uri.path == '/groups/10/members') {
        return [
          {'id': 10, 'nickname': '서연', 'is_current_user': true},
          {'id': 11, 'nickname': '지연', 'is_current_user': false},
        ];
      }
      return null;
    });
    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: GroupsScreen())),
      );
      await tester.pumpAndSettle();
      expect(find.text('실제 서버 모임'), findsOneWidget);
      expect(find.text('연남 산책단'), findsNothing);
      await tester.tap(find.text('실제 서버 모임'));
      await tester.pumpAndSettle();
      expect(find.text('모임 관리'), findsOneWidget);
      expect(find.textContaining('멤버 2명'), findsOneWidget);
      expect(find.text('서연'), findsOneWidget);
      expect(find.text('지연'), findsOneWidget);
      expect(find.text('나'), findsOneWidget);
      expect(find.text('멤버 상세 정보가 제공되지 않았어요.'), findsNothing);
      expect(find.text('소개/공유 범위 저장'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }, createHttpClient: (_) => server);
  });

  testWidgets('invite sheet keeps copy and removes the unused share action', (
    tester,
  ) async {
    ApiTransport.setAccessToken('group-test-token');
    final server = _Client((request) {
      if (request.uri.path == '/groups' && request.method == 'GET') {
        return [groupResponse()];
      }
      if (request.uri.path.endsWith('/invite')) {
        return {'invite_code': 'COPY-ONLY-CODE'};
      }
      return null;
    });
    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: GroupsScreen())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.ios_share_outlined));
      await tester.pumpAndSettle();
      expect(find.text('코드 복사'), findsOneWidget);
      expect(find.text('공유하기'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    }, createHttpClient: (_) => server);
  });

  testWidgets('group query failure exposes retry instead of fake empty data', (
    tester,
  ) async {
    final server = _Client((request) => {'detail': '서버 조회 실패'}, status: 500);
    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: GroupsScreen())),
      );
      await tester.pumpAndSettle();
      expect(find.text('서버 조회 실패 다시 시도'), findsOneWidget);
      expect(find.text('참여 중인 모임이 없어요.'), findsNothing);
      await tester.tap(find.text('서버 조회 실패 다시 시도'));
      await tester.pumpAndSettle();
      expect(server.requests, hasLength(2));
      await tester.pumpWidget(const SizedBox());
    }, createHttpClient: (_) => server);
  });
}

class _Client implements HttpClient {
  _Client(this.respond, {this.status = 200});
  final Object? Function(_Request request) respond;
  final int status;
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
