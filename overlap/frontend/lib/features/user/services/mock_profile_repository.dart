import '../models/profile_summary_data.dart';

/// Neutral zero state until profile data is loaded from the API.
abstract final class MockProfileRepository {
  static const profile = ProfileSummaryData(
    userName: '내 프로필',
    statusText: '',
    recordCount: 0,
    visitedPlaceCount: 0,
    groupCount: 0,
    recentRecordTitle: '',
    recentRecordPlace: '',
  );
}
