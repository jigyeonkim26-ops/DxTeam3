class MockGroupInvite {
  const MockGroupInvite({required this.code, required this.shareLink});

  final String code;
  final String shareLink;
}

/// API 연결 전 모임 생성 결과를 확인하기 위한 임시 초대 정보 생성기입니다.
abstract final class MockGroupInviteService {
  static MockGroupInvite create() {
    final seed = DateTime.now().microsecondsSinceEpoch
        .toRadixString(36)
        .toUpperCase();
    final suffix = seed.substring(seed.length - 4);
    final code = 'YN-$suffix';

    return MockGroupInvite(
      code: code,
      shareLink: 'https://overlap.app/join-group?code=$code',
    );
  }
}
