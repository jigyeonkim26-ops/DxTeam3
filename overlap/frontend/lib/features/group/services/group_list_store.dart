import 'package:flutter/foundation.dart';

import '../models/group_list_item_data.dart';
import 'group_api_service.dart';
import '../../../core/network/api_transport.dart';
import '../../../core/network/api_client.dart' show ApiClient;

/// API 응답을 화면 간에 전달하기 위한 메모리 캐시입니다.
abstract final class GroupListStore {
  static final ValueNotifier<List<GroupListItemData>> groupsListenable =
      _createGroupsListenable();

  static ValueNotifier<List<GroupListItemData>> _createGroupsListenable() {
    ApiClient.sessionRevision.addListener(clear);
    return ValueNotifier<List<GroupListItemData>>([]);
  }

  static int _generation = 0;

  static Future<void> refreshGroups() async {
    final generation = ++_generation;
    final token = ApiTransport.accessToken;
    final response = await GroupApiService.listGroups();
    if (generation != _generation || token != ApiTransport.accessToken) return;
    final previous = {for (final group in groups) group.id: group};
    replaceGroups([
      for (final group in response)
        GroupListItemData(
          id: group.id.toString(),
          name: group.displayName ?? group.name,
          memberCount: group.memberCount,
          placeCount: previous['${group.id}']?.placeCount ?? 0,
          newRecordCount: previous['${group.id}']?.newRecordCount ?? 0,
          recordCount: previous['${group.id}']?.recordCount ?? 0,
          inviteCode: previous['${group.id}']?.inviteCode ?? '',
          members: previous['${group.id}']?.members ?? const [],
          description: group.description,
          visibility: group.visibility,
          notificationsEnabled: group.notificationsEnabled,
          pinColorValue: group.pinColorValue,
        ),
    ]);
  }

  static void clear() {
    _generation++;
    replaceGroups([]);
  }

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
