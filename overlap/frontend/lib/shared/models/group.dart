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
}
