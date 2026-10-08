import '../models/group_invite_preview.dart';

/// API 연결 전 초대 코드 확인 화면에 제공하는 고정 mock 데이터입니다.
abstract final class MockGroupJoinService {
  static GroupInvitePreview previewForCode(String inviteCode) {
    return GroupInvitePreview(
      groupName: '연남 산책단',
      ownerName: '서연',
      memberCount: 3,
      placeCount: 8,
      inviteCode: inviteCode,
    );
  }
}
