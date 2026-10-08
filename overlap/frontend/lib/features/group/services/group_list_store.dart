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
  static bool _hasLoadedGroups = false;
  static Future<void>? _refreshInFlight;
  static bool _refreshIncludesRecordStatistics = false;

  static bool get hasLoadedGroups => _hasLoadedGroups;

  static Future<void> refreshGroups({bool includeRecordStatistics = false}) {
    final pending = _refreshInFlight;
    if (pending != null) {
      if (!includeRecordStatistics || _refreshIncludesRecordStatistics) {
        return pending;
      }
      return pending.then((_) => refreshGroups(includeRecordStatistics: true));
    }

    final operation = _refreshGroups(
      includeRecordStatistics: includeRecordStatistics,
    );
    _refreshInFlight = operation;
    _refreshIncludesRecordStatistics = includeRecordStatistics;
    return operation.whenComplete(() {
      if (identical(_refreshInFlight, operation)) {
        _refreshInFlight = null;
        _refreshIncludesRecordStatistics = false;
      }
    });
  }

  static Future<void> _refreshGroups({
    required bool includeRecordStatistics,
  }) async {
    final generation = ++_generation;
    final token = ApiTransport.accessToken;
    final response = await GroupApiService.listGroups();
    if (generation != _generation || token != ApiTransport.accessToken) return;
    final previous = {for (final group in groups) group.id: group};
    final statistics = includeRecordStatistics
        ? await Future.wait(response.map(_loadRecordStatistics))
        : List<GroupRecordStatistics?>.filled(response.length, null);
    if (generation != _generation || token != ApiTransport.accessToken) return;
    _hasLoadedGroups = true;
    replaceGroups([
      for (var index = 0; index < response.length; index++)
        _toListItem(
          response[index],
          previous: previous['${response[index].id}'],
          placeCount: statistics[index]?.placeCount,
          recordCount: statistics[index]?.recordCount,
        ),
    ]);
  }

  static Future<GroupRecordStatistics?> _loadRecordStatistics(
    GroupApiItem group,
  ) async {
    try {
      return await GroupApiService.getRecordStatistics(group.id);
    } on ApiException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static void clear() {
    _generation++;
    _hasLoadedGroups = false;
    groupsListenable.value = const [];
  }

  /// Makes a successful create or join available to every listener immediately.
  /// A later server refresh keeps aggregate statistics and server-side settings
  /// authoritative.
  static void upsertGroup(GroupApiItem group, {String? inviteCode}) {
    _generation++;
    _hasLoadedGroups = true;
    final current = List<GroupListItemData>.of(groupsListenable.value);
    final index = current.indexWhere((item) => item.id == '${group.id}');
    final previous = index == -1 ? null : current[index];
    final item = _toListItem(group, previous: previous, inviteCode: inviteCode);
    if (index == -1) {
      current.add(item);
    } else {
      current[index] = item;
    }
    replaceGroups(current);
  }

  static GroupListItemData _toListItem(
    GroupApiItem group, {
    GroupListItemData? previous,
    int? placeCount,
    int? recordCount,
    String? inviteCode,
  }) => GroupListItemData(
    id: group.id.toString(),
    name: group.displayName ?? group.name,
    memberCount: group.memberCount,
    placeCount: placeCount ?? previous?.placeCount,
    newRecordCount: previous?.newRecordCount,
    recordCount: recordCount ?? previous?.recordCount,
    inviteCode: inviteCode ?? previous?.inviteCode ?? '',
    members: previous?.members ?? const [],
    description: group.description,
    visibility: group.visibility,
    notificationsEnabled: group.notificationsEnabled,
    pinColorValue: group.pinColorValue,
  );

  static void replaceGroups(List<GroupListItemData> groups) {
    _hasLoadedGroups = true;
    groupsListenable.value = List<GroupListItemData>.unmodifiable(groups);
  }

  static List<GroupListItemData> get groups =>
      List<GroupListItemData>.unmodifiable(groupsListenable.value);

  static bool removeGroupFromCache(String groupId) {
    final updatedGroups = groupsListenable.value
        .where((group) => group.id != groupId)
        .toList(growable: false);
    if (updatedGroups.length == groupsListenable.value.length) return false;

    _generation++;
    _hasLoadedGroups = true;
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

  /// Applies only a successful server response to the shared group cache.
  static bool updateMembers(
    String groupId,
    List<GroupMemberData> members,
  ) {
    final current = groupsListenable.value;
    final index = current.indexWhere((group) => group.id == groupId);
    if (index == -1) return false;

    final updated = List<GroupListItemData>.of(current)
      ..[index] = current[index].copyWith(
        memberCount: members.length,
        members: List<GroupMemberData>.unmodifiable(members),
      );
    groupsListenable.value = List<GroupListItemData>.unmodifiable(updated);
    return true;
  }
}
