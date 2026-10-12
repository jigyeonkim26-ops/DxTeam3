import 'package:flutter_test/flutter_test.dart';
import 'package:overlap_app/features/map/models/map_filter.dart';
import 'package:overlap_app/features/map/models/map_place.dart';
import 'package:overlap_app/features/map/services/kakao_map_local_server.dart';

void main() {
  const red = MapFilter.group(10, 'same name', pinColorValue: 0xFFFF0000);
  const blue = MapFilter.group(30, 'same name', pinColorValue: 0xFF0000FF);
  const duplicate = MapFilter.group(40, 'red again', pinColorValue: 0xFFFF0000);
  const missing = MapFilter.group(50, 'no color');
  final place = MapPlace.tryFromMapPlacesApiJson({
    'place_id': 14,
    'name': 'Shared place',
    'record_count': 8,
    'latitude': 35.1,
    'longitude': 126.8,
    'has_mine': true,
    'group_ids': [10, 30, 40, 50],
    'has_multi_group_record': false,
  })!;
  const available = [MapFilter.mine, red, blue, duplicate, missing];
  test('group IDs distinguish identical names and survive renaming', () {
    expect(red, isNot(blue));
    expect(red, const MapFilter.group(10, 'renamed'));
  });
  test(
    'different records at one place retain count and use one solid color',
    () {
      final pin = place.forSelectedFilters(
        available.toSet(),
        available,
        isAll: true,
      );
      expect(pin.id, '14');
      expect(pin.recordCount, 8);
      expect(pin.groupColorHexes, ['#FF0000']);
      expect(pin.hasMultiGroupRecord, isFalse);
      expect(pin.groupColorHex, isNot(MapGroupColors.pearSorbet));
    },
  );
  test('map renderer never generates split or gradient pins', () {
    final page = KakaoMapLocalServer().debugMapPage('offline-key');
    expect(page, isNot(contains('linearGradient')));
    expect(page, isNot(contains('pin-gradient')));
    expect(
      page,
      contains("setProperty('--pin-fill', markerColor(place.groupColorHex))"),
    );
  });
  test('only selected group colors are displayed', () {
    expect(place.forSelectedFilters({blue}, available).groupColorHexes, [
      '#0000FF',
    ]);
    expect(place.forSelectedFilters({red}, available).groupColorHexes, [
      '#FF0000',
    ]);
  });
  test(
    'multi-group record metadata survives filtering and preserves A/B colors',
    () {
      final shared = MapPlace.tryFromMapPlacesApiJson({
        'place_id': 14,
        'name': 'Shared record',
        'record_count': 1,
        'latitude': 35.1,
        'longitude': 126.8,
        'group_ids': [10, 30],
        'has_multi_group_record': true,
      })!;
      final a = shared.forSelectedFilters({red}, available);
      final b = shared.forSelectedFilters({blue}, available);
      final all = shared.forSelectedFilters(
        available.toSet(),
        available,
        isAll: true,
      );
      expect(all.groupColorHex, '#F5EDC9');
      expect(all.groupColorHexes, ['#F5EDC9']);
      expect(all.recordCount, 1);
      expect(all.id, shared.id);
      expect(a.hasMultiGroupRecord, isTrue);
      expect(b.hasMultiGroupRecord, isTrue);
      expect(a.groupColorHexes, ['#FF0000']);
      expect(b.groupColorHexes, ['#0000FF']);
      expect(a.recordCount, 1);
      expect(b.recordCount, 1);
    },
  );
  test('missing group color and own-only records use default', () {
    expect(place.forSelectedFilters({missing}, available).groupColorHexes, [
      MapGroupColors.fallback,
    ]);
    expect(
      place.forSelectedFilters({MapFilter.mine}, available).groupColorHexes,
      [MapGroupColors.fallback],
    );
  });
  test('API membership does not assign unrelated filters to a pin', () {
    expect(
      place.filters.contains(const MapFilter.group(999, 'unrelated')),
      isFalse,
    );
    final private = MapPlace.tryFromMapPlacesApiJson({
      'place_id': 15,
      'name': 'Private',
      'record_count': 1,
      'latitude': 35.1,
      'longitude': 126.8,
      'has_mine': true,
      'group_ids': [],
    })!;
    expect(private.filters, {MapFilter.mine});
    expect(
      private
          .forSelectedFilters(available.toSet(), available, isAll: true)
          .groupColorHex,
      MapGroupColors.fallback,
    );
  });
}
