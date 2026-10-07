import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:overlap_app/features/map/models/map_search_place.dart';
import 'package:overlap_app/shared/models/place.dart';

void main() {
  test(
    'converts a selected Place without changing its coordinates or name',
    () {
      final place = Place(
        id: 'kakao-1',
        name: '카페 "봄"',
        address: '서울, 성수동',
        latitude: 37.55,
        longitude: 127.01,
      );

      final searchPlace = MapSearchPlace.fromPlace(place);

      expect(searchPlace.name, place.name);
      expect(searchPlace.latitude, place.latitude);
      expect(searchPlace.longitude, place.longitude);
      expect(searchPlace.address, place.address);
      expect(searchPlace.hasValidCoordinates, isTrue);
    },
  );

  test('encodes search place data as safe JSON with Korean and quotes', () {
    const place = MapSearchPlace(
      id: 'kakao-2',
      name: '카페 "봄"',
      address: '서울, 성수동',
      latitude: 37.55,
      longitude: 127.01,
    );

    final decoded = jsonDecode(place.toJsonString()) as Map<String, dynamic>;

    expect(decoded['name'], '카페 "봄"');
    expect(decoded['address'], '서울, 성수동');
    expect(decoded['latitude'], 37.55);
    expect(decoded['longitude'], 127.01);
  });

  test('rejects coordinates outside geographic bounds', () {
    const place = MapSearchPlace(
      id: 'invalid',
      name: '잘못된 좌표',
      latitude: 91,
      longitude: 127,
    );

    expect(place.hasValidCoordinates, isFalse);
  });
}
