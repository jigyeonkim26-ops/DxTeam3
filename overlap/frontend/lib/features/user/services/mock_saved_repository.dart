import '../models/saved_item_data.dart';

abstract final class MockSavedRepository {
  static const wishPlaces = [
    SavedItemData(
      title: '양림동 펭귄마을',
      description: '친구 2명이 먼저 다녀왔어요',
      metaText: '기억 3개 · 방문 전 잠김',
      itemType: SavedItemType.wishPlace,
      thumbnailLabel: '펭',
    ),
    SavedItemData(
      title: '광주 CGI센터',
      description: '연남 산책단의 다음 약속 장소',
      metaText: '기억 4개 · 방문 확인 가능',
      itemType: SavedItemType.wishPlace,
      thumbnailLabel: 'CGI',
    ),
  ];
  static const myRecords = [
    SavedItemData(
      title: '광주 CGI센터',
      description: '2026.09.22',
      metaText: '사진 1장 · 댓글 2',
      itemType: SavedItemType.myRecord,
      thumbnailLabel: 'CGI',
    ),
  ];
}
