import 'map_filter.dart';

/// 지도 SDK와 분리된, 화면 표시용 장소 데이터입니다.
class MapPlace {
  const MapPlace({
    required this.id,
    required this.name,
    required this.recordCount,
    required this.author,
    required this.summary,
    required this.latitude,
    required this.longitude,
    required this.filters,
  });

  final String id;
  final String name;
  final int recordCount;
  final String author;
  final String summary;
  final double latitude;
  final double longitude;
  final Set<MapFilter> filters;
}
