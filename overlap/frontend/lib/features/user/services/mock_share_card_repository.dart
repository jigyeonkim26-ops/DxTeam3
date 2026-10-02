import '../models/share_card_data.dart';

abstract final class MockShareCardRepository {
  static const card = ShareCardData(
    dateText: '2026.09.22',
    placeName: '연남동 작은 카페',
    memoryText: '비 오는 날, 창가 자리',
    photoCount: 1,
    aspectRatioText: '1:1',
    themeText: '오프화이트',
  );
}
