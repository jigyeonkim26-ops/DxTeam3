import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:overlap_app/features/memory/screens/record_detail_screen.dart';
import 'package:overlap_app/features/memory/screens/record_edit_screen.dart';
import 'package:overlap_app/features/memory/services/record_api.dart';
import 'package:overlap_app/shared/models/emotion.dart';
import 'package:overlap_app/shared/models/record.dart';

Map<String, dynamic> _recordJson({
  String content = '수정 전 내용',
  String emotion = 'good',
  bool isPrivate = true,
  List<Map<String, dynamic>> sharedGroups = const [],
}) => {
  'id': 1,
  'author': {'id': 7, 'name': '작성자'},
  'place': {
    'id': 2,
    'name': '기존 장소',
    'address': '서울',
    'latitude': 37.5,
    'longitude': 127.0,
  },
  'created_at': '2026-10-08T00:00:00Z',
  'content': content,
  'emotion': emotion,
  'is_private': isPrivate,
  'photo_urls': ['/records/1/photos/3'],
  'shared_groups': sharedGroups,
};

void main() {
  test(
    'update and delete use the authenticated API and signal record revision',
    () async {
      final revision = RecordApi.revision.value;
      final requests = <http.Request>[];
      final api = RecordApi(
        tokenProvider: () => 'test-token',
        client: MockClient((request) async {
          requests.add(request);
          if (request.method == 'PATCH') {
            expect(request.url.path, '/records/1');
            expect(request.headers['authorization'], 'Bearer test-token');
            expect(jsonDecode(request.body), {
              'content': '수정한 내용',
              'emotion': 'excellent',
              'is_private': false,
              'group_ids': [10],
            });
            return http.Response(
              jsonEncode(
                _recordJson(
                  content: '수정한 내용',
                  emotion: 'excellent',
                  isPrivate: false,
                  sharedGroups: [
                    {'id': 10, 'name': '실제 가입 모임'},
                  ],
                ),
              ),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          expect(request.method, 'DELETE');
          expect(request.url.path, '/records/1');
          return http.Response('', 204);
        }),
      );

      final updated = await api.update(
        recordId: '1',
        content: '수정한 내용',
        emotion: Emotion.excellent,
        isPrivate: false,
        groupIds: {'10'},
      );
      await api.delete('1');

      expect(updated.content, '수정한 내용');
      expect(updated.sharedGroups.single.id, '10');
      expect(requests, hasLength(2));
      expect(RecordApi.revision.value, revision + 2);
      api.close();
    },
  );

  testWidgets(
    'record edit loads the current values and saves the selected scope',
    (tester) async {
      late Map<String, dynamic> patchPayload;
      final api = RecordApi(
        tokenProvider: () => 'token',
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(
              jsonEncode([
                {'id': 10, 'name': '실제 가입 모임', 'member_count': 2},
              ]),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          patchPayload = Map<String, dynamic>.from(jsonDecode(request.body));
          return http.Response(
            jsonEncode(
              _recordJson(
                content: '변경한 내용',
                emotion: 'excellent',
                isPrivate: false,
                sharedGroups: [
                  {'id': 10, 'name': '실제 가입 모임'},
                ],
              ),
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      Record? saved;
      final record = Record.fromJson(
        _recordJson(
          isPrivate: false,
          sharedGroups: [
            {'id': 10, 'name': '실제 가입 모임'},
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                saved = await Navigator.of(context).push<Record>(
                  MaterialPageRoute<Record>(
                    builder: (_) =>
                        RecordEditScreen(record: record, recordApi: api),
                  ),
                );
              },
              child: const Text('수정 열기'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('수정 열기'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '수정 전 내용',
      );
      await tester.enterText(find.byType(TextField), '변경한 내용');
      await tester.tap(find.text('최고예요'));
      await tester.scrollUntilVisible(
        find.byKey(const Key('record-edit-save')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const Key('record-edit-save')));
      await tester.pumpAndSettle();

      expect(patchPayload, {
        'content': '변경한 내용',
        'emotion': 'excellent',
        'is_private': false,
        'group_ids': [10],
      });
      expect(saved?.content, '변경한 내용');
      api.close();
    },
  );

  testWidgets(
    'canceling record deletion keeps the detail screen and sends no request',
    (tester) async {
      var requests = 0;
      final api = RecordApi(
        tokenProvider: () => 'token',
        client: MockClient((_) async {
          requests++;
          return http.Response('', 204);
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: RecordDetailScreen(
            record: Record.fromJson(_recordJson()),
            recordApi: api,
            canManage: true,
          ),
        ),
      );
      await tester.tap(find.byTooltip('기록 메뉴'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      expect(find.text('기록을 삭제할까요?'), findsOneWidget);
      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();

      expect(requests, 0);
      expect(find.text('기록 상세'), findsOneWidget);
      api.close();
    },
  );

  testWidgets(
    'confirmed record deletion requests the API and returns the deleted id',
    (tester) async {
      var requests = 0;
      final api = RecordApi(
        tokenProvider: () => 'token',
        client: MockClient((request) async {
          requests++;
          expect(request.method, 'DELETE');
          expect(request.url.path, '/records/1');
          return http.Response('', 204);
        }),
      );
      RecordDetailResult? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await Navigator.of(context).push<RecordDetailResult>(
                  MaterialPageRoute<RecordDetailResult>(
                    builder: (_) => RecordDetailScreen(
                      record: Record.fromJson(_recordJson()),
                      recordApi: api,
                      canManage: true,
                    ),
                  ),
                );
              },
              child: const Text('상세 열기'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('상세 열기'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('기록 메뉴'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('삭제'));
      await tester.pumpAndSettle();

      expect(requests, 1);
      expect(result?.deletedRecordId, '1');
      api.close();
    },
  );

  testWidgets('failed record deletion keeps the detail screen visible', (
    tester,
  ) async {
    final api = RecordApi(
      tokenProvider: () => 'token',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'detail': '삭제할 수 없습니다.'}),
          503,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: RecordDetailScreen(
          record: Record.fromJson(_recordJson()),
          recordApi: api,
          canManage: true,
        ),
      ),
    );
    await tester.tap(find.byTooltip('기록 메뉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();

    expect(find.text('기록 상세'), findsOneWidget);
    expect(find.text('삭제할 수 없습니다.'), findsOneWidget);
    api.close();
  });
}
