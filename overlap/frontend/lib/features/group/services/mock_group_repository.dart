import 'package:flutter/foundation.dart';

import '../models/group_list_item_data.dart';

/// Groups are populated only after the group API is connected.
abstract final class MockGroupRepository {
  static final groupsListenable = ValueNotifier<List<GroupListItemData>>(
    const [],
  );

  static List<GroupListItemData> get groups =>
      List<GroupListItemData>.unmodifiable(groupsListenable.value);

  static List<GroupMemberData> membersFor(GroupListItemData group) => const [];

  static void updateGroup(GroupListItemData group) {}

  static bool leaveGroup(String groupId) => false;
}
