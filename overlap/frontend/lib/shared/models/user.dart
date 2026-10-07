/// 기록과 모임에서 공통으로 참조하는 사용자 정보입니다.
class User {
  const User({required this.id, required this.name, this.profileImagePath});

  final String id;
  final String name;
  final String? profileImagePath;
}
