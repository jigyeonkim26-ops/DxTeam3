import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overlap_app/core/network/api_transport.dart';
import 'package:overlap_app/features/group/models/group_list_item_data.dart';
import 'package:overlap_app/features/group/screens/group_detail_management_screen.dart';
import 'package:overlap_app/features/group/services/group_list_store.dart';

void main() {
  setUp(() {
    ApiTransport.setAccessToken('member-test-token');
    GroupListStore.replaceGroups([
      const GroupListItemData(
        id: '10',
        name: '실제 모임',
        memberCount: 2,
        placeCount: 0,
        newRecordCount: 0,
        inviteCode: 'TEST-CODE',
      ),
    ]);
  });

  tearDown(() {
    ApiTransport.clearAccessToken();
    GroupListStore.clear();
  });

  testWidgets('member management shows loading then every real member and me', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final response = Completer<List<GroupMemberData>>();
    await tester.pumpWidget(
      MaterialApp(
        home: GroupDetailManagementScreen(
          groupId: '10',
          memberLoader: (_) => response.future,
        ),
      ),
    );

    expect(find.text('멤버 목록을 불러오는 중이에요.'), findsOneWidget);
    response.complete(const [
      GroupMemberData(id: '1', nickname: '우진', isCurrentUser: true),
      GroupMemberData(id: '2', nickname: '지연'),
      GroupMemberData(id: '3', nickname: '민지'),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('우진'), findsOneWidget);
    expect(find.text('지연'), findsOneWidget);
    expect(find.text('민지'), findsOneWidget);
    expect(find.text('나'), findsOneWidget);
    expect(find.textContaining('멤버 3명'), findsOneWidget);
    expect(find.text('멤버 상세 정보가 제공되지 않았어요.'), findsNothing);
  });

  testWidgets(
    'member request failure provides retry and re-entry loads fresh data',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      var requestCount = 0;
      Future<List<GroupMemberData>> loadMembers(int _) async {
        requestCount++;
        if (requestCount == 1) {
          throw const ApiException('멤버 목록을 불러오지 못했습니다.');
        }
        return const [
          GroupMemberData(id: '4', nickname: '새 멤버', isCurrentUser: true),
        ];
      }

      Future<void> open() => tester.pumpWidget(
        MaterialApp(
          home: GroupDetailManagementScreen(
            groupId: '10',
            memberLoader: loadMembers,
          ),
        ),
      );

      await open();
      await tester.pumpAndSettle();
      expect(find.text('멤버 목록을 불러오지 못했습니다.'), findsOneWidget);
      expect(find.text('다시 시도'), findsOneWidget);

      await tester.tap(find.text('다시 시도'));
      await tester.pumpAndSettle();
      expect(find.text('새 멤버'), findsOneWidget);
      expect(find.text('나'), findsOneWidget);
      expect(requestCount, 2);

      await tester.pumpWidget(const SizedBox());
      await open();
      await tester.pumpAndSettle();
      expect(find.text('새 멤버'), findsOneWidget);
      expect(requestCount, 3);
    },
  );
}
