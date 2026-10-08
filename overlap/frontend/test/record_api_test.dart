import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:overlap_app/core/network/api_client.dart';
import 'package:overlap_app/features/memory/screens/feed_screen.dart';
import 'package:overlap_app/features/memory/services/record_api.dart';
import 'package:overlap_app/shared/models/emotion.dart';
import 'package:overlap_app/shared/models/place.dart';

Map<String, dynamic> recordJson() => {
  'id': 1,
  'author': {'id': 7, 'name': '실제 작성자'},
  'place': {
    'id': 2,
    'name': '선택한 장소',
    'address': '서울',
    'latitude': 37.5,
    'longitude': 127.0,
  },
  'created_at': '2026-10-07T00:00:00Z',
  'content': '',
  'emotion': 'good',
  'is_private': true,
  'photo_urls': ['/records/1/photos/3'],
  'shared_groups': [],
};

void main() {
  test('multipart save sends authenticated photos and optional story; private excludes groups', () async {
    final revision = RecordApi.revision.value;
    late http.Request captured;
    final api = RecordApi(
      tokenProvider: () => 'test-token',
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode(recordJson()),
          201,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final result = await api.create(
      photos: [
        XFile.fromData(Uint8List.fromList([1, 2, 3]), path: 'actual.png'),
      ],
      emotion: Emotion.good,
      place: const Place(
        id: '123',
        name: '선택한 장소',
        latitude: 37.5,
        longitude: 127,
      ),
      content: '',
      isPrivate: true,
      groupIds: {'10'},
    );
    expect(captured.url.path, '/records');
    expect(captured.headers['authorization'], 'Bearer test-token');
    expect(captured.headers['content-type'], contains('multipart/form-data'));
    final body = utf8.decode(captured.bodyBytes);
    expect(body, contains('name="photos"; filename="actual.png"'));
    expect(body, contains('"group_ids":[]'));
    expect(body, contains('"content":""'));
    expect(body, contains('"kakao_place_id":"123"'));
    expect(result.isPrivate, true);
    expect(result.imagePaths, ['/records/1/photos/3']);
    expect(RecordApi.revision.value, revision + 1);
    api.close();
  });

  test('feed sends real group filter and follows pagination', () async {
    final api = RecordApi(
      tokenProvider: () => 'token',
      client: MockClient((request) async {
        expect(request.url.queryParameters['group_id'], '10');
        final offset = request.url.queryParameters['offset'];
        return http.Response(
          jsonEncode({
            'items': offset == '0' ? [recordJson()] : [],
            'total': 2,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    expect((await api.feed(groupId: '10')).length, 1);
    api.close();
  });

  test('failed save does not signal success', () async {
    final revision = RecordApi.revision.value;
    final api = RecordApi(
      tokenProvider: () => 'token',
      client: MockClient(
        (_) async => http.Response('{"detail":"storage unavailable"}', 503),
      ),
    );
    await expectLater(
      api.create(
        photos: [],
        emotion: Emotion.good,
        place: const Place(id: '123', name: '장소', latitude: 37, longitude: 127),
        content: '',
        isPrivate: true,
        groupIds: {},
      ),
      throwsA(isA<ApiException>()),
    );
    expect(RecordApi.revision.value, revision);
    api.close();
  });

  testWidgets(
    'empty personalized feed has no virtual posts and filters only actual memberships',
    (tester) async {
      final api = RecordApi(
        tokenProvider: () => 'token',
        client: MockClient(
          (request) async => http.Response(
            jsonEncode(
              request.url.path == '/records/groups'
                  ? [
                      {'id': 10, 'name': '실제 가입 모임', 'member_count': 2},
                    ]
                  : {'items': [], 'total': 0},
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FeedScreen(recordApi: api)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('피드'), findsOneWidget);
      expect(find.text('표시할 기록이 없어요.'), findsOneWidget);
      expect(find.text('서연'), findsNothing);
      await tester.tap(find.text('내 맞춤 피드'));
      await tester.pumpAndSettle();
      expect(find.text('실제 가입 모임'), findsOneWidget);
      expect(find.text('동네 친구들'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
}
