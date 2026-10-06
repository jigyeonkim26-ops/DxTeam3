import '../models/profile_summary_data.dart';

abstract final class MockProfileRepository {
  static const profile = ProfileSummaryData(
    userName: '서연',
    statusText: '연남 산책단 · 참여 중',
    recordCount: 12,
    visitedPlaceCount: 7,
    groupCount: 3,
    recentRecordTitle: '비 오는 날, 창가 자리',
    recentRecordPlace: '연남동 작은 카페',
  );
}
