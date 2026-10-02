import '../models/group_list_item_data.dart';

/// API 연결 전 모임 목록 화면에 제공하는 고정 데이터입니다.
abstract final class MockGroupRepository {
  static const List<GroupListItemData> groups = [
    GroupListItemData(
      id: 'yeonnam',
      name: '연남 산책단',
      memberCount: 3,
      placeCount: 8,
      newRecordCount: 2,
      hasTodayNewRecords: true,
      isInitiallySelected: true,
    ),
    GroupListItemData(
      id: 'neighborhood',
      name: '동네 친구들',
      memberCount: 5,
      placeCount: 14,
      newRecordCount: 0,
    ),
    GroupListItemData(
      id: 'travel',
      name: '여행팟',
      memberCount: 4,
      placeCount: 20,
      newRecordCount: 2,
    ),
  ];
}
