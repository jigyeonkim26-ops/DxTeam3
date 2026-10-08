import 'package:flutter_test/flutter_test.dart';
import 'package:overlap_app/features/user/models/user_profile.dart';

void main() {
  test(
    'parses the current-user API response without sample profile values',
    () {
      final profile = UserProfile.fromJson({
        'id': 42,
        'email': 'member@example.com',
        'nickname': '실제 사용자',
        'birth_date': '1997-04-18',
        'gender': 'female',
      });

      expect(profile.id, 42);
      expect(profile.nickname, '실제 사용자');
      expect(profile.birthDateText, '1997-04-18');
      expect(profile.genderLabel, '여성');
    },
  );

  test('rejects an incomplete current-user API response', () {
    expect(
      () => UserProfile.fromJson({
        'id': 42,
        'email': 'member@example.com',
        'nickname': '실제 사용자',
      }),
      throwsFormatException,
    );
  });
}
