class ProfileSummaryData {
  const ProfileSummaryData({
    required this.userName,
    required this.statusText,
    required this.recordCount,
    required this.visitedPlaceCount,
    required this.groupCount,
    required this.recentRecordTitle,
    required this.recentRecordPlace,
  });
  final String userName;
  final String statusText;
  final int recordCount;
  final int visitedPlaceCount;
  final int groupCount;
  final String recentRecordTitle;
  final String recentRecordPlace;
}
