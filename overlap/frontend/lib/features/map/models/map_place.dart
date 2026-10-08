import 'map_filter.dart';

/// Shared default colors; API group colors are accepted independently.
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
    this.groupColorHexes = const [],
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
  final List<String> groupColorHexes;

  MapPlace forSelectedFilters(
    Set<MapFilter> selected,
    List<MapFilter> available,
  ) {
    final colors = <String>{};
    for (final filter in available) {
      if (filter.groupId != null &&
          selected.contains(filter) &&
          filters.contains(filter)) {
        colors.add(
          '#${((filter.pinColorValue ?? 0xFF14364A) & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
        );
      }
    }
    if (colors.isEmpty) colors.add(MapGroupColors.fallback);
    return withColors(colors.toList());
  }

  MapPlace withColors(List<String> colors) => MapPlace(
    id: id,
    name: name,
    recordCount: recordCount,
    author: author,
    summary: summary,
    latitude: latitude,
    longitude: longitude,
    filters: filters,
    groupColorHex: colors.isEmpty ? MapGroupColors.fallback : colors.first,
    groupColorHexes: colors,
  );

  /// Converts the authenticated `/map/places` response into the map's
  /// existing marker model. Invalid entries are ignored by the caller.
  static MapPlace? tryFromMapPlacesApiJson(Map<String, dynamic> json) {
    final id = _asId(json['place_id']);
    final name = json['name'];
    final recordCount = _asInt(json['record_count']);
    final latitude = _asDouble(json['latitude']);
    final longitude = _asDouble(json['longitude']);
    if (id == null ||
        name is! String ||
        name.trim().isEmpty ||
        recordCount == null ||
        recordCount < 0 ||
        latitude == null ||
        longitude == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      return null;
    }

    return MapPlace(
      id: id,
      name: name.trim(),
      recordCount: recordCount,
      author: '',
      summary: '',
      latitude: latitude,
      longitude: longitude,
      filters: {
        if (json['has_mine'] == true) MapFilter.mine,
        for (final id in (json['group_ids'] as List? ?? const []))
          if (id is int && id > 0) MapFilter.group(id, ''),
      },
      groupColorHex: MapGroupColors.fallback,
    );
  }

  static String? _asId(Object? value) {
    if (value is int && value > 0) return value.toString();
    final parsed = int.tryParse(value?.toString() ?? '');
    return parsed != null && parsed > 0 ? parsed.toString() : null;
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _asDouble(Object? value) {
    final number = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    return number != null && number.isFinite ? number : null;
  }
}
