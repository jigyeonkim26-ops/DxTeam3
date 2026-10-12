import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overlap_app/features/user/models/user_profile.dart';
import 'package:overlap_app/features/user/screens/profile_edit_screen.dart';

void main() {
  testWidgets('logout is secondary to save and keeps its confirmation dialog', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileEditScreen(
          profile: UserProfile(
            id: 7,
            email: 'user@example.com',
            nickname: 'Tester',
            birthDate: DateTime(1997, 4, 18),
            gender: 'female',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(FilledButton), findsOneWidget);
    final logoutFinder = find.byKey(const Key('profile-logout'));
    await tester.scrollUntilVisible(
      logoutFinder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.byType(Divider), findsOneWidget);
    final saveRect = tester.getRect(find.byType(FilledButton));
    final logoutRect = tester.getRect(logoutFinder);
    expect(logoutRect.width, lessThan(saveRect.width));

    await tester.tap(logoutFinder);
    await tester.pumpAndSettle();
    expect(find.text('로그아웃할까요?'), findsOneWidget);
    await tester.tap(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('취소')),
    );
    await tester.pumpAndSettle();
    expect(find.text('로그아웃할까요?'), findsNothing);
  });
}
