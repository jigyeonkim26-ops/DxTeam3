import 'package:flutter_test/flutter_test.dart';

import 'package:overlap_app/main.dart';

void main() {
  testWidgets('app starts on the login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const OverlapApp());

    expect(find.text('OVERLAP', findRichText: true), findsOneWidget);
    expect(find.text('로그인'), findsOneWidget);
  });
}
