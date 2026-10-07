import 'package:flutter/foundation.dart';

import '../models/group_list_item_data.dart';

/// API 응답을 화면 간에 전달하기 위한 메모리 캐시입니다.
abstract final class GroupListStore {
  static final ValueNotifier<List<GroupListItemData>> groupsListenable =
      ValueNotifier<List<GroupListItemData>>([]);

  static void replaceGroups(List<GroupListItemData> groups) {
    groupsListenable.value = List<GroupListItemData>.unmodifiable(groups);
  }

  static List<GroupListItemData> get groups =>
      List<GroupListItemData>.unmodifiable(groupsListenable.value);

  static bool removeGroupFromCache(String groupId) {
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
