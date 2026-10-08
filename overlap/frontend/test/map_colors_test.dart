import 'package:flutter_test/flutter_test.dart';
import 'package:overlap_app/features/map/models/map_filter.dart';
import 'package:overlap_app/features/map/models/map_place.dart';

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
  })!;
  const available = [MapFilter.mine, red, blue, duplicate, missing];
  test('group IDs distinguish identical names and survive renaming', () {
    expect(red, isNot(blue));
    expect(red, const MapFilter.group(10, 'renamed'));
  });
  test(
    'one place retains total count and all distinct selected group colors',
    () {
      final pin = place.forSelectedFilters({red, blue, duplicate}, available);
      expect(pin.id, '14');
      expect(pin.recordCount, 8);
      expect(pin.groupColorHexes, ['#FF0000', '#0000FF']);
    },
  );
  test('only selected group colors are displayed', () {
    expect(place.forSelectedFilters({blue}, available).groupColorHexes, [
      '#0000FF',
    ]);
    expect(place.forSelectedFilters({red}, available).groupColorHexes, [
      '#FF0000',
    ]);
  });
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
  });
}
