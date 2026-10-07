import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:overlap_app/features/memory/screens/feed_screen.dart';
import 'package:overlap_app/features/memory/services/record_api.dart';
import 'package:overlap_app/features/memory/widgets/record_card.dart';

import 'record_api_test.dart' show recordJson;

void main() {
  testWidgets(
    'multiple actual groups union server records without duplicates',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final queries = <Uri>[];
      final api = RecordApi(
        tokenProvider: () => 'test-token',
        client: MockClient((request) async {
          if (request.url.path == '/records/groups') {
            return http.Response(
              jsonEncode([
                {'id': 10, 'name': '실제 모임 A'},
                {'id': 20, 'name': '실제 모임 B'},
                {'id': 30, 'name': '실제 모임 C'},
              ]),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          queries.add(request.url);
          final shared = recordJson()..['id'] = 1;
          final unique = recordJson()
            ..['id'] = 2
            ..['content'] = 'B의 기록';
          return http.Response(
            jsonEncode({
              'items': request.url.queryParameters['group_id'] == '20'
                  ? [shared, unique]
                  : [shared],
              'total': request.url.queryParameters['group_id'] == '20' ? 2 : 1,
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: FeedScreen(recordApi: api)),
        ),
      );
      await tester.pumpAndSettle();
      queries.clear();
      await tester.tap(find.text('내 맞춤 피드'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('전체'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('실제 모임 A'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('실제 모임 B'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('필터 적용하기'));
      await tester.pumpAndSettle();
      expect(queries.map((uri) => uri.queryParameters['group_id']).toSet(), {
        '10',
        '20',
      });
      expect(
        queries.every((uri) => !uri.queryParameters.containsKey('mine')),
        isTrue,
      );
      expect(find.byType(RecordCard), findsNWidgets(2));
      expect(find.text('2개 선택'), findsOneWidget);
      expect(find.text('실제 모임 C'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      api.close();
    },
  );
}
