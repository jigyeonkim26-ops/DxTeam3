import '../models/notification_item_data.dart';

abstract final class MockNotificationRepository {
  static const items = [
    NotificationItemData(
      type: NotificationType.newRecord,
      title: '민지가 새 기록을 남겼어요.',
      description: '연남동 작은 카페 · 산책 끝의 따뜻한 커피',
      timeText: '방금 전',
      isRead: false,
    ),
    NotificationItemData(
      type: NotificationType.comment,
      title: '수연님이 회원님의 기록에 댓글을 남겼어요.',
      description: '다음엔 맑은 날에도 가보자!',
      timeText: '18분 전',
      isRead: false,
    ),
    NotificationItemData(
      type: NotificationType.placeUpdate,
      title: '연남동 작은 카페의 새 사진이 쌓였어요.',
      description: '연남 산책단 · 새 기록 2개',
      timeText: '어제',
      isRead: true,
    ),
    NotificationItemData(
      type: NotificationType.groupInvite,
      title: '동네 친구들 모임에 초대되었어요.',
      description: '초대를 수락하면 모임 기록을 볼 수 있어요.',
      timeText: '3일 전',
      isRead: true,
    ),
  ];
}
