import '../../../core/network/api_transport.dart';
import '../models/group_list_item_data.dart';

class GroupApiItem {
  const GroupApiItem({
    required this.id,
    required this.name,
    required this.memberCount,
    this.displayName,
    this.description,
    this.visibility = 'INVITED_ONLY',
    this.notificationsEnabled = true,
    this.pinColorValue,
  });

  final int id;
  final String name;
  final int memberCount;
  final String? displayName;
  final String? description;
  final String visibility;
  final bool notificationsEnabled;
  final int? pinColorValue;

  factory GroupApiItem.fromJson(Map<String, dynamic> json) => GroupApiItem(
    id: json['id'] as int,
    name: json['name'] as String,
    memberCount: json['member_count'] as int,
    displayName: json['display_name'] as String?,
    description: json['description'] as String?,
    visibility: json['visibility'] as String? ?? 'INVITED_ONLY',
    notificationsEnabled: json['notifications_enabled'] as bool? ?? true,
    pinColorValue: json['pin_color_value'] as int?,
  );
}

class GroupApiCreated extends GroupApiItem {
  const GroupApiCreated({
    required super.id,
    required super.name,
    required super.memberCount,
    super.displayName,
    required this.inviteCode,
  });

  final String inviteCode;

  factory GroupApiCreated.fromJson(Map<String, dynamic> json) =>
      GroupApiCreated(
        id: json['id'] as int,
        name: json['name'] as String,
        memberCount: json['member_count'] as int,
        displayName: json['display_name'] as String?,
        inviteCode: json['invite_code'] as String,
      );
}

class GroupMemberApiItem {
  const GroupMemberApiItem({
    required this.id,
    required this.nickname,
    required this.isCurrentUser,
    this.profileImageUrl,
  });

  final int id;
  final String nickname;
  final bool isCurrentUser;
  final String? profileImageUrl;

  factory GroupMemberApiItem.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final nickname = json['nickname'];
    final isCurrentUser = json['is_current_user'];
    if (id is! int || nickname is! String || isCurrentUser is! bool) {
      throw const FormatException('Invalid group member response.');
    }
    return GroupMemberApiItem(
      id: id,
      nickname: nickname,
      isCurrentUser: isCurrentUser,
      profileImageUrl: json['profile_image_url'] as String?,
    );
  }

  GroupMemberData toData() => GroupMemberData(
    id: '$id',
    nickname: nickname,
    isCurrentUser: isCurrentUser,
    profileImageUrl: profileImageUrl,
  );
}

class GroupRecordStatistics {
  const GroupRecordStatistics({
    required this.recordCount,
    required this.placeCount,
  });

  final int recordCount;
  final int placeCount;
}

abstract final class GroupApiService {
  static Future<List<GroupApiItem>> listGroups() async {
    final response = await ApiTransport.get('/groups');
    if (response is! List) {
      throw const ApiException('모임 목록 응답을 확인할 수 없습니다.');
    }
    return response
        .whereType<Map<String, dynamic>>()
        .map(GroupApiItem.fromJson)
        .toList(growable: false);
  }

  static Future<List<GroupMemberData>> getGroupMembers(int groupId) async {
    final response = await ApiTransport.get('/groups/$groupId/members');
    if (response is! List) {
      throw const ApiException('모임 멤버 응답을 확인할 수 없습니다.');
    }
    try {
      return response
          .map((member) {
            if (member is! Map<String, dynamic>) {
              throw const FormatException('Invalid group member response.');
            }
            return GroupMemberApiItem.fromJson(member);
          })
          .map((member) => member.toData())
          .toList(growable: false);
    } on FormatException {
      throw const ApiException('모임 멤버 응답을 확인할 수 없습니다.');
    }
  }

  /// Calculates group statistics from the existing paginated group feed.
  ///
  /// The groups API does not provide record or distinct-place aggregates, so
  /// every page is required to make the place count exact.
  static Future<GroupRecordStatistics> getRecordStatistics(int groupId) async {
    final placeIds = <Object>{};
    var offset = 0;

    while (true) {
      final response = await ApiTransport.get(
        '/feed?group_id=$groupId&limit=100&offset=$offset',
      );
      if (response is! Map ||
          response['items'] is! List ||
          response['total'] is! int) {
        throw const ApiException('모임 기록 통계 응답을 확인할 수 없습니다.');
      }

      final items = response['items'] as List;
      for (final item in items) {
        if (item is! Map || item['place'] is! Map) {
          throw const ApiException('모임 기록 통계 응답을 확인할 수 없습니다.');
        }

        final placeId = (item['place'] as Map)['id'];
        if (placeId == null) {
          throw const ApiException('모임 기록 통계 응답을 확인할 수 없습니다.');
        }
        placeIds.add(placeId);
      }

      offset += items.length;
      final total = response['total'] as int;
      if (items.isEmpty || offset >= total) {
        return GroupRecordStatistics(
          recordCount: total,
          placeCount: placeIds.length,
        );
      }
    }
  }

  static Future<GroupApiCreated> createGroup({
    required String name,
    required String? description,
    required String visibility,
  }) async {
    final response = await ApiTransport.post(
      '/groups',
      body: {
        'name': name.trim(),
        'description': description?.trim().isEmpty == true
            ? null
            : description?.trim(),
        'visibility': visibility,
      },
    );
    if (response is! Map<String, dynamic>) {
      throw const ApiException('모임 생성 응답을 확인할 수 없습니다.');
    }
    return GroupApiCreated.fromJson(response);
  }

  static Future<GroupApiItem> updateGroupDetails({
    required int id,
    required String? description,
    required String visibility,
  }) async {
    final response = await ApiTransport.put(
      '/groups/$id',
      body: {'description': description, 'visibility': visibility},
    );
    if (response is! Map<String, dynamic>) {
      throw const ApiException('모임 수정 응답을 확인할 수 없습니다.');
    }
    return GroupApiItem.fromJson(response);
  }

  static Future<GroupApiItem> updatePreferences({
    required int id,
    bool updateCustomName = false,
    String? customName,
    bool? notificationsEnabled,
    int? pinColorValue,
  }) async {
    final body = <String, dynamic>{};
    if (updateCustomName) body['custom_name'] = customName;
    if (notificationsEnabled != null) {
      body['notifications_enabled'] = notificationsEnabled;
    }
    if (pinColorValue != null) {
      body['pin_color_value'] = pinColorValue;
    }
    final response = await ApiTransport.patch(
      '/groups/$id/preferences',
      body: body,
    );
    if (response is! Map<String, dynamic>) {
      throw const ApiException('모임 환경설정 응답을 확인할 수 없습니다.');
    }
    return GroupApiItem.fromJson(response);
  }

  static Future<void> leaveGroup(int id) async =>
      ApiTransport.delete('/groups/$id/members/me');

  static Future<GroupApiItem> joinGroup(String inviteCode) async {
    final response = await ApiTransport.post(
      '/groups/join',
      body: {'invite_code': inviteCode.trim()},
    );
    if (response is! Map<String, dynamic>) {
      throw const ApiException('모임 가입 응답을 확인할 수 없습니다.');
    }
    return GroupApiItem.fromJson(response);
  }

  static Future<String> getInviteCode(int groupId) async {
    final response = await ApiTransport.get('/groups/$groupId/invite');
    if (response is! Map<String, dynamic> ||
        response['invite_code'] is! String) {
      throw const ApiException('초대 코드 응답을 확인할 수 없습니다.');
    }
    return response['invite_code'] as String;
  }
}
