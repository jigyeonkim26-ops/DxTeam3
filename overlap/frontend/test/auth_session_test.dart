import 'package:flutter_test/flutter_test.dart';
import 'package:overlap_app/core/network/api_client.dart';
import 'package:overlap_app/main.dart';

void main() {
  tearDown(ApiClient.clearSession);

  testWidgets(
    'expired authenticated session returns to the login screen once',
    (tester) async {
      ApiClient.setAccessToken('test-token');
      await tester.pumpWidget(const OverlapApp());

      expect(ApiClient.expireSession(), isTrue);
      await tester.pumpAndSettle();

      expect(ApiClient.accessToken, isNull);
      expect(ApiClient.sessionExpired, isTrue);
      expect(find.text('로그인 정보가 만료되었거나 취소되었습니다. 다시 로그인해 주세요.'), findsOneWidget);

      expect(ApiClient.expireSession(), isFalse);
    },
  );
}
