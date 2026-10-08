/// 실제 모임 API 응답과 화면 표시 정보를 함께 보관합니다.
class GroupListItemData {
  const GroupListItemData({
    required this.id,
    required this.name,
    required this.memberCount,
    required this.placeCount,
    required this.newRecordCount,
    required this.inviteCode,
    this.recordCount = 0,
    this.pinColorValue = 0xFFFF7058,
    this.notificationsEnabled = true,
    List<GroupMemberData> members = const [],
    this.description,
    this.visibility = 'INVITED_ONLY',
    this.hasTodayNewRecords = false,
    this.isInitiallySelected = false,
    // ignore: prefer_initializing_formals
  }) : _members = members;

  final String id;
  final String name;
  final String? description;
  final String visibility;
  final int memberCount;
  final int placeCount;
  final int newRecordCount;
  final String inviteCode;
  final int? recordCount;
  final int? pinColorValue;
  final bool? notificationsEnabled;
  final List<GroupMemberData>? _members;
  List<GroupMemberData> get members => _members ?? const [];
  final bool hasTodayNewRecords;
  final bool isInitiallySelected;

  String get inviteUrl => 'https://overlap.app/join/$inviteCode';

  GroupListItemData copyWith({
    String? name,
    int? memberCount,
    List<GroupMemberData>? members,
    String? description,
    String? visibility,
    int? pinColorValue,
    bool? notificationsEnabled,
  }) {
    return GroupListItemData(
      id: id,
      name: name ?? this.name,
      memberCount: memberCount ?? this.memberCount,
      placeCount: placeCount,
      newRecordCount: newRecordCount,
      inviteCode: inviteCode,
      recordCount: recordCount ?? 0,
      pinColorValue: pinColorValue ?? this.pinColorValue ?? 0xFFFF7058,
      notificationsEnabled:
          notificationsEnabled ?? this.notificationsEnabled ?? true,
      members: members ?? this.members,
      description: description ?? this.description,
      visibility: visibility ?? this.visibility,
      hasTodayNewRecords: hasTodayNewRecords,
      isInitiallySelected: isInitiallySelected,
    );
  }

  String get newRecordDescription {
    if (newRecordCount == 0) {
      return '새 기록 없음';
    }

    final prefix = hasTodayNewRecords ? '오늘 새 기록' : '새 기록';
    return '$prefix $newRecordCount개';
  }
}

class GroupMemberData {
  const GroupMemberData({
    required this.id,
    required this.nickname,
    this.profileImagePath,
  });

  final String id;
  final String nickname;
  final String? profileImagePath;
}
