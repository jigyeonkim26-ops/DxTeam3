/// 모임 목록 화면에서만 사용하는 표시용 mock data 모델입니다.
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
    this.hasTodayNewRecords = false,
    this.isInitiallySelected = false,
    // ignore: prefer_initializing_formals
  }) : _members = members;

  final String id;
  final String name;
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
    int? pinColorValue,
    bool? notificationsEnabled,
  }) {
    return GroupListItemData(
      id: id,
      name: name ?? this.name,
      memberCount: memberCount,
      placeCount: placeCount,
      newRecordCount: newRecordCount,
      inviteCode: inviteCode,
      recordCount: recordCount ?? 0,
      pinColorValue: pinColorValue ?? this.pinColorValue ?? 0xFFFF7058,
      notificationsEnabled:
          notificationsEnabled ?? this.notificationsEnabled ?? true,
      members: members,
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
