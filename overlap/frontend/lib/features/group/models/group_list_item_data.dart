/// 모임 목록 화면에서만 사용하는 표시용 mock data 모델입니다.
class GroupListItemData {
  const GroupListItemData({
    required this.id,
    required this.name,
    required this.memberCount,
    required this.placeCount,
    required this.newRecordCount,
    this.hasTodayNewRecords = false,
    this.isInitiallySelected = false,
  });

  final String id;
  final String name;
  final int memberCount;
  final int placeCount;
  final int newRecordCount;
  final bool hasTodayNewRecords;
  final bool isInitiallySelected;

  String get newRecordDescription {
    if (newRecordCount == 0) {
      return '새 기록 없음';
    }

    final prefix = hasTodayNewRecords ? '오늘 새 기록' : '새 기록';
    return '$prefix $newRecordCount개';
  }
}
