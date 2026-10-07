import 'package:flutter/foundation.dart';

import '../models/group_list_item_data.dart';

/// API 연결 전 모임 목록 화면에 제공하는 고정 데이터입니다.
abstract final class MockGroupRepository {
  static final ValueNotifier<List<GroupListItemData>> groupsListenable =
      ValueNotifier<List<GroupListItemData>>([
        GroupListItemData(
          id: 'yeonnam',
          name: '연남 산책단',
          memberCount: 3,
          placeCount: 8,
          newRecordCount: 2,
          inviteCode: 'YN1234',
          recordCount: 12,
          hasTodayNewRecords: true,
          isInitiallySelected: true,
        ),
        GroupListItemData(
          id: 'neighborhood',
          name: '동네 친구들',
          memberCount: 5,
          placeCount: 14,
          newRecordCount: 0,
          inviteCode: 'FRIEND5',
          recordCount: 8,
        ),
        GroupListItemData(
          id: 'travel',
          name: '여행팟',
          memberCount: 4,
          placeCount: 20,
          newRecordCount: 2,
          inviteCode: 'TRIP20',
          recordCount: 16,
        ),
      ]);

  static List<GroupListItemData> get groups =>
      List<GroupListItemData>.unmodifiable(groupsListenable.value);

  static bool leaveGroup(String groupId) {
    final updatedGroups = groupsListenable.value
        .where((group) => group.id != groupId)
        .toList(growable: false);
    if (updatedGroups.length == groupsListenable.value.length) return false;

    groupsListenable.value = updatedGroups;
    return true;
  }

  static bool updateGroup(GroupListItemData updatedGroup) {
    final groups = groupsListenable.value;
    final groupIndex = groups.indexWhere(
      (group) => group.id == updatedGroup.id,
    );
    if (groupIndex == -1) return false;

    final updatedGroups = List<GroupListItemData>.of(groups)
      ..[groupIndex] = updatedGroup;
    groupsListenable.value = updatedGroups;
    return true;
  }
}
