import 'map_filter.dart';

/// Current group-color defaults shared with the community UI.
///
/// These values are defaults for mock data only; [MapPlace.groupColorHex] is
/// intentionally not limited to this list so future group colors flow through
/// to the map without a map-code update.
abstract final class MapGroupColors {
  static const coral = '#FF7058';
  static const deepNavy = '#14364A';
  static const green = '#6FAE8F';
  static const amber = '#F0B35D';
  static const purple = '#8C7BBD';

  static const fallback = deepNavy;
}

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
    required this.groupColorHex,
  });

  final String id;
  final String name;
  final int recordCount;
  final String author;
  final String summary;
  final double latitude;
  final double longitude;
  final Set<MapFilter> filters;
  final String groupColorHex;
}
