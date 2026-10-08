import 'package:flutter/foundation.dart';

import '../models/group_list_item_data.dart';

/// API 연결 전 모임 목록 화면에 제공하는 고정 데이터입니다.
abstract final class MockGroupRepository {
  static const _membersByGroupId = <String, List<GroupMemberData>>{
    'yeonnam': [
      GroupMemberData(id: 'seoyeon', nickname: '서연'),
      GroupMemberData(id: 'minji', nickname: '민지'),
      GroupMemberData(id: 'jiyeon', nickname: '지연'),
    ],
    'neighborhood': [
      GroupMemberData(id: 'seoyeon', nickname: '서연'),
      GroupMemberData(id: 'suyeon', nickname: '수연'),
      GroupMemberData(id: 'doyoon', nickname: '도윤'),
      GroupMemberData(id: 'haneul', nickname: '하늘'),
      GroupMemberData(id: 'jiwoo', nickname: '지우'),
    ],
    'travel': [
      GroupMemberData(id: 'seoyeon', nickname: '서연'),
      GroupMemberData(id: 'yujin', nickname: '유진'),
      GroupMemberData(id: 'chaewon', nickname: '채원'),
      GroupMemberData(id: 'minseok', nickname: '민석'),
    ],
  };

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
          members: _membersByGroupId['yeonnam']!,
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
          members: _membersByGroupId['neighborhood']!,
        ),
        GroupListItemData(
          id: 'travel',
          name: '여행팟',
          memberCount: 4,
          placeCount: 20,
          newRecordCount: 2,
          inviteCode: 'TRIP20',
          recordCount: 16,
          members: _membersByGroupId['travel']!,
        ),
      ]);

  static List<GroupListItemData> get groups =>
      List<GroupListItemData>.unmodifiable(groupsListenable.value);

  static List<GroupMemberData> membersFor(GroupListItemData group) {
    final members = group.members;
    if (members.isNotEmpty) return members;
    return _membersByGroupId[group.id] ?? const <GroupMemberData>[];
  }

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
