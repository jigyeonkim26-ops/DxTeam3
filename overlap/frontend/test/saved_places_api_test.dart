import 'package:flutter_test/flutter_test.dart';
import 'package:overlap_app/features/user/services/saved_places_api.dart';

Map<String, dynamic> savedPlaceJson() => {
  'place_id': 12,
  'name': '광주실감콘텐츠큐브',
  'address': '광주광역시',
  'road_address': '광주광역시 동구',
  'latitude': 35.1107137,
  'longitude': 126.8778041,
  'created_at': '2026-10-08T00:00:00Z',
};

Map<String, dynamic> savedStateJson(bool saved) => {
  'place_id': 12,
  'saved': saved,
  'saved_count': saved ? 1 : 0,
};

void main() {
  test('parses the saved places page using the backend endpoint', () async {
    final requests = <String>[];
    final api = SavedPlacesApi(
      get: (path) async {
        requests.add(path);
        return {
          'items': [savedPlaceJson()],
          'total': 1,
          'offset': 0,
          'limit': 100,
        };
      },
    );

    final places = await api.list();

    expect(requests, ['/places/saved?offset=0&limit=100']);
    expect(places.single.placeId, 12);
    expect(places.single.name, '광주실감콘텐츠큐브');
    expect(places.single.displayAddress, '광주광역시 동구');
  });

  test('uses POST and DELETE for save changes and parses the returned state', () async {
    final requests = <String>[];
    final api = SavedPlacesApi(
      post: (path) async {
        requests.add('POST $path');
        return savedStateJson(true);
      },
      delete: (path) async {
        requests.add('DELETE $path');
        return savedStateJson(false);
      },
    );

    expect((await api.save(12)).saved, isTrue);
    expect((await api.unsave(12)).saved, isFalse);
    expect(requests, ['POST /places/12/saved', 'DELETE /places/12/saved']);
  });
}
