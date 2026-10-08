import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:overlap_app/features/memory/screens/feed_screen.dart';
import 'package:overlap_app/features/memory/services/record_api.dart';
import 'package:overlap_app/features/memory/widgets/record_card.dart';
import 'package:overlap_app/shared/models/group.dart';
import 'package:overlap_app/shared/models/record.dart';

import 'record_api_test.dart' show recordJson;

RecordApi responseApi(Object groups, Object feed) => RecordApi(
  tokenProvider: () => 'test-token',
  client: MockClient(
    (request) async => http.Response(
      jsonEncode(request.url.path == '/records/groups' ? groups : feed),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    ),
  ),
);

Future<void> showFeed(WidgetTester tester, RecordApi api) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: FeedScreen(recordApi: api)),
    ),
  );
  await tester.pumpAndSettle();
}

class PendingFeedApi extends RecordApi {
  final responses = <Completer<List<Record>>>[];
  @override
  Future<List<Group>> groups() async => [];
  @override
  Future<List<Record>> feed({bool mine = false, String? groupId}) {
    final response = Completer<List<Record>>();
    responses.add(response);
    return response.future;
  }
}

void main() {
  for (final missing in [true, false]) {
    testWidgets(
      '200 record with ${missing ? 'missing' : 'null'} photo_urls displays card',
      (tester) async {
        final json = recordJson();
        if (missing) {
          json.remove('photo_urls');
        } else {
          json['photo_urls'] = null;
        }
        final api = responseApi([], {
          'items': [json],
          'total': 1,
        });
        await showFeed(tester, api);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(RecordCard), findsOneWidget);
        expect(find.text('실제 작성자'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        api.close();
      },
    );
  }

  testWidgets('200 empty feed ends loading and displays empty state', (
    tester,
  ) async {
    final api = responseApi([], {'items': [], 'total': 0});
    await showFeed(tester, api);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('표시할 기록이 없어요.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  for (final invalidGroups in [false, true]) {
    testWidgets(
      '200 malformed ${invalidGroups ? 'groups' : 'record'} ends loading and supports retry',
      (tester) async {
        final json = recordJson()..['created_at'] = 'invalid date';
        final api = responseApi(
          invalidGroups
              ? [
                  {'id': 1, 'name': 42},
                ]
              : [],
          {
            'items': [json],
            'total': 1,
          },
        );
        await showFeed(tester, api);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('피드 응답을 읽지 못했습니다. 다시 시도'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('피드 응답을 읽지 못했습니다. 다시 시도'));
        await tester.pumpAndSettle();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await tester.pumpWidget(const SizedBox());
        api.close();
      },
    );
  }

  testWidgets('stale response does not stop latest loading; latest completes', (
    tester,
  ) async {
    final api = PendingFeedApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FeedScreen(recordApi: api)),
      ),
    );
    await tester.pump();
    RecordApi.revision.value++;
    await tester.pump();
    expect(api.responses.length, 2);
    api.responses[0].complete([]);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    api.responses[1].complete([]);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('표시할 기록이 없어요.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets('completion after dispose never updates unmounted screen', (
    tester,
  ) async {
    final api = PendingFeedApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: FeedScreen(recordApi: api)),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    api.responses.single.completeError(
      const FormatException('invalid response'),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    api.close();
  });
}
