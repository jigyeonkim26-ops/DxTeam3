class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    required this.nickname,
    required this.birthDate,
    required this.gender,
  });

  final int id;
  final String email;
  final String nickname;
  final DateTime birthDate;
  final String gender;

  String get birthDateText =>
      '${birthDate.year.toString().padLeft(4, '0')}-'
      '${birthDate.month.toString().padLeft(2, '0')}-'
      '${birthDate.day.toString().padLeft(2, '0')}';

  String get genderLabel => switch (gender) {
    'female' => '여성',
    'male' => '남성',
    _ => gender,
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = switch (rawId) {
      int value => value,
      num value => value.toInt(),
      String value => int.tryParse(value),
      _ => null,
    };
    final email = json['email'];
    final nickname = json['nickname'];
    final gender = json['gender'];
    final rawBirthDate = json['birth_date'];
    final birthDate = rawBirthDate is String
        ? DateTime.tryParse(rawBirthDate)
        : null;

    if (id == null ||
        email is! String ||
        nickname is! String ||
        gender is! String ||
        birthDate == null) {
      throw const FormatException('Invalid current-user response.');
    }

    return UserProfile(
      id: id,
      email: email,
      nickname: nickname,
      birthDate: birthDate,
      gender: gender,
    );
  }
}
