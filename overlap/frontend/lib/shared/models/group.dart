/// 기록 공유 범위를 구성하는 모임 정보입니다.
class Group {
  const Group({
    required this.id,
    required this.name,
    this.description = '',
    this.memberCount = 0,
    this.inviteCode,
  });

  final String id;
  final String name;
  final String description;
  final int memberCount;
  final String? inviteCode;

  factory Group.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId is int ? rawId : int.tryParse(rawId?.toString() ?? '');
    final name = json['name'];
    if (id == null || id <= 0 || name is! String) {
      throw const FormatException('Invalid group response.');
    }

    final rawMemberCount = json['member_count'];
    final memberCount = rawMemberCount is num
        ? rawMemberCount.toInt()
        : int.tryParse(rawMemberCount?.toString() ?? '') ?? 0;
    final rawInviteCode = json['invite_code'];

    return Group(
      id: id.toString(),
      name: name,
      memberCount: memberCount,
      inviteCode: rawInviteCode is String ? rawInviteCode : null,
    );
  }
}
