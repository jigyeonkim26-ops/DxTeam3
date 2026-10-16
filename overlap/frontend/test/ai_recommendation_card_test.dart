import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:overlap_app/core/network/api_client.dart';
import 'package:overlap_app/core/network/api_config.dart';
import 'package:overlap_app/features/ai/models/ai_place_recommendation.dart';
import 'package:overlap_app/features/ai/screens/ai_recommendation_screen.dart';
import 'package:overlap_app/features/ai/services/ai_recommendations_api.dart';
import 'package:overlap_app/features/ai/widgets/ai_place_recommendation_card.dart';
import 'package:overlap_app/features/map/screens/place_detail_screen.dart';
import 'package:overlap_app/features/memory/services/record_api.dart';
import 'package:overlap_app/features/user/services/saved_places_api.dart';

const recommendation = AiPlaceRecommendation(
  kakaoPlaceId: '12345',
  name: '아주 긴 이름의 카카오 검증 장소 양림동 펭귄마을',
  address: '광주광역시 남구 양림동 길고 자세한 실제 주소',
  latitude: 35.14,
  longitude: 126.91,
  reason: '산책했던 기록과 조용한 공간을 좋아하는 취향에 잘 맞는 장소입니다.',
  sourceUrl: 'https://place.map.kakao.com/12345',
  matchedKeywords: ['산책', '조용한 공간'],
);

class _Recommendations extends AiRecommendationsApi {
  @override
  Future<List<AiPlaceRecommendation>> load() async => [recommendation];
}

class _EmptyRecommendations extends AiRecommendationsApi {
  @override
  Future<List<AiPlaceRecommendation>> load() async => [];
}

class _ExhaustedRecommendations extends AiRecommendationsApi {
  var calls = 0;

  @override
  Future<List<AiPlaceRecommendation>> load() async {
    calls++;
    if (calls == 1) return [recommendation];
    sessionStatus = 'exhausted';
    return [];
  }
}

class _PagedRecommendations extends AiRecommendationsApi {
  var calls = 0;
  final pages = <List<AiPlaceRecommendation>>[];
  final statuses = <String>[];

  @override
  Future<List<AiPlaceRecommendation>> load() async {
    final index = calls++;
    sessionStatus = statuses[index];
    return pages[index];
  }
}

AiPlaceRecommendation pageRecommendation(String id) => AiPlaceRecommendation(
  kakaoPlaceId: id,
  name: 'Place $id',
  address: 'Test street',
  latitude: 35.1,
  longitude: 126.9,
  reason: 'Matches the user preference',
  sourceUrl: 'https://place.map.kakao.com/$id',
  matchedKeywords: const ['quiet'],
);

Widget card(
  SavedPlacesApi api,
  VoidCallback onTap, {
  AiPlaceRecommendation item = recommendation,
}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 280,
        child: AiPlaceRecommendationCard(
          recommendation: item,
          onTap: onTap,
          savedPlacesApi: api,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('empty recommendation response explains how to retry', (
    tester,
  ) async {
    final api = SavedPlacesApi(
      get: (_) async => {'place_id': null, 'saved': false, 'record_count': 0},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiRecommendationContent(
            api: _EmptyRecommendations(),
            savedPlacesApi: api,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('취향에 맞는 장소를 아직 찾지 못했어요.'), findsOneWidget);
    expect(find.text('다시 추천받기'), findsOneWidget);
  });

  testWidgets('exhausted refresh keeps cards and shows a separate notice', (
    tester,
  ) async {
    final recommendationsApi = _ExhaustedRecommendations();
    AiPlaceRecommendation? selected;
    final savedApi = SavedPlacesApi(
      get: (_) async => {'place_id': null, 'saved': false, 'record_count': 0},
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiRecommendationContent(
            api: recommendationsApi,
            onRecommendationSelected: (item) => selected = item,
            savedPlacesApi: savedApi,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(recommendation.name), findsOneWidget);

    await tester.tap(find.text('다음 장소 추천받기'));
    await tester.pumpAndSettle();

    expect(find.text(recommendation.name), findsOneWidget);
    expect(find.text('1곳'), findsOneWidget);
    expect(find.text('지금은 새로운 추천 장소가 더 없어요.'), findsOneWidget);
    expect(find.text('다음 장소 추천받기'), findsNothing);
    expect(find.text('처음 추천 다시 보기'), findsNothing);
    expect(recommendationsApi.calls, 2);

    await tester.tap(find.text(recommendation.name));
    expect(identical(selected, recommendation), isTrue);
  });

  testWidgets('replays every received page locally after exhaustion', (
    tester,
  ) async {
    final recommendationsApi = _PagedRecommendations()
      ..pages.addAll([
        [
          pageRecommendation('A'),
          pageRecommendation('B'),
          pageRecommendation('C'),
        ],
        [
          pageRecommendation('D'),
          pageRecommendation('E'),
          pageRecommendation('F'),
        ],
        [
          pageRecommendation('G'),
          pageRecommendation('H'),
          pageRecommendation('I'),
        ],
        const [],
      ])
      ..statuses.addAll(['available', 'available', 'available', 'exhausted']);
    final savedApi = SavedPlacesApi(
      get: (_) async => {'place_id': null, 'saved': false, 'record_count': 0},
    );
    AiPlaceRecommendation? selectedAfterReplay;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiRecommendationContent(
            api: recommendationsApi,
            onRecommendationSelected: (item) => selectedAfterReplay = item,
            savedPlacesApi: savedApi,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Place A'), findsOneWidget);

    Future<void> next() async {
      await tester.tap(find.text('다음 장소 추천받기'));
      await tester.pumpAndSettle();
    }

    await next();
    expect(find.text('Place D'), findsOneWidget);
    await next();
    expect(find.text('Place G'), findsOneWidget);
    await next();
    expect(find.text('지금은 새로운 추천 장소가 더 없어요.'), findsOneWidget);
    expect(find.text('다음 장소 추천받기'), findsNothing);
    expect(find.text('처음 추천 다시 보기'), findsOneWidget);
    expect(recommendationsApi.calls, 4);

    await tester.tap(find.text('처음 추천 다시 보기'));
    await tester.pumpAndSettle();
    expect(find.text('Place A'), findsOneWidget);
    expect(find.text('지금은 새로운 추천 장소가 더 없어요.'), findsNothing);
    expect(find.text('처음 추천 다시 보기'), findsNothing);
    expect(find.text('다음 장소 추천받기'), findsOneWidget);
    await next();
    expect(find.text('Place D'), findsOneWidget);
    expect(find.text('지금은 새로운 추천 장소가 더 없어요.'), findsNothing);
    expect(find.text('처음 추천 다시 보기'), findsNothing);
    await next();
    expect(find.text('Place G'), findsOneWidget);
    expect(find.text('지금은 새로운 추천 장소가 더 없어요.'), findsOneWidget);
    expect(find.text('처음 추천 다시 보기'), findsOneWidget);
    expect(recommendationsApi.calls, 4);
    await tester.tap(find.text('Place G'));
    expect(selectedAfterReplay?.kakaoPlaceId, 'G');
  });

  testWidgets('renders all backend results and a one-place final page', (
    tester,
  ) async {
    final recommendationsApi = _PagedRecommendations()
      ..pages.addAll([
        [
          pageRecommendation('A'),
          pageRecommendation('B'),
          pageRecommendation('C'),
        ],
        [pageRecommendation('D')],
      ])
      ..statuses.addAll(['available', 'exhausted']);
    final savedApi = SavedPlacesApi(
      get: (_) async => {'place_id': null, 'saved': false, 'record_count': 0},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiRecommendationContent(
            api: recommendationsApi,
            savedPlacesApi: savedApi,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('3\uACF3'), findsOneWidget);
    expect(find.text('Place A'), findsOneWidget);
    expect(find.text('Place B'), findsOneWidget);
    expect(find.text('Place C'), findsOneWidget);

    await tester.tap(find.text('다음 장소 추천받기'));
    await tester.pumpAndSettle();
    expect(find.text('1\uACF3'), findsOneWidget);
    expect(find.text('Place D'), findsOneWidget);
    expect(find.text('지금은 새로운 추천 장소가 더 없어요.'), findsOneWidget);
    expect(find.text('처음 추천 다시 보기'), findsOneWidget);
  });

  testWidgets(
    'small card shows text and a category placeholder without an image URL',
    (tester) async {
      final api = SavedPlacesApi(
        get: (_) async => {'place_id': null, 'saved': false, 'record_count': 0},
      );
      var selections = 0;
      await tester.pumpWidget(card(api, () => selections++));
      await tester.pumpAndSettle();

      expect(find.text(recommendation.name), findsOneWidget);
      expect(find.text(recommendation.address!), findsOneWidget);
      expect(find.text(recommendation.reason), findsOneWidget);
      expect(find.text('산책'), findsOneWidget);
      expect(find.text('조용한 공간'), findsOneWidget);
      expect(find.byIcon(Icons.park_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text(recommendation.name));
      expect(selections, 1);
    },
  );

  test('older recommendation JSON defaults to a placeholder image', () {
    final item = AiPlaceRecommendation.fromJson({
      'kakao_place_id': '12345',
      'name': '죽녹원',
      'address': '전라남도 담양군',
      'latitude': 35.3,
      'longitude': 126.9,
      'reason': '산책 취향과 맞아요.',
      'source_url': 'https://place.map.kakao.com/12345',
      'matched_keywords': ['산책'],
    });
    expect(item.imageUrl, isNull);
    expect(item.imageOriginType, 'placeholder');
  });

  testWidgets('image URL renders a thumbnail and failed loading falls back', (
    tester,
  ) async {
    final api = SavedPlacesApi(
      get: (_) async => {'place_id': null, 'saved': false, 'record_count': 0},
    );
    final item = AiPlaceRecommendation(
      kakaoPlaceId: recommendation.kakaoPlaceId,
      name: recommendation.name,
      address: recommendation.address,
      latitude: recommendation.latitude,
      longitude: recommendation.longitude,
      reason: recommendation.reason,
      sourceUrl: recommendation.sourceUrl,
      matchedKeywords: recommendation.matchedKeywords,
      imageUrl: 'https://images.example.test/thumbnail.jpg',
      imageSource: 'kakao_daum_image_search',
      imageOriginType: 'external',
      imageCredit: '전남 여행 기록',
    );
    await tester.pumpWidget(card(api, () {}, item: item));
    expect(
      find.byWidgetPredicate((widget) => widget is Image && widget.width == 84),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(find.text('전남 여행 기록'), findsNothing);
    expect(find.byIcon(Icons.park_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'private record thumbnail uses the authenticated record photo endpoint',
    (tester) async {
      ApiClient.setAccessToken('user-photo-token');
      addTearDown(ApiClient.clearSession);
      final api = SavedPlacesApi(
        get: (_) async => {'place_id': null, 'saved': false, 'record_count': 0},
      );
      final item = AiPlaceRecommendation(
        kakaoPlaceId: recommendation.kakaoPlaceId,
        name: recommendation.name,
        address: recommendation.address,
        latitude: recommendation.latitude,
        longitude: recommendation.longitude,
        reason: recommendation.reason,
        sourceUrl: recommendation.sourceUrl,
        matchedKeywords: recommendation.matchedKeywords,
        imageUrl: '/records/7/photos/11',
        imageSource: 'overlap_record',
        imageOriginType: 'record',
        imageCredit: 'OVERLAP 기록 사진',
      );
      await tester.pumpWidget(card(api, () {}, item: item));
      final image = tester.widget<Image>(
        find.byWidgetPredicate(
          (widget) => widget is Image && widget.width == 84,
        ),
      );
      final provider =
          (image.image as ResizeImage).imageProvider as NetworkImage;
      expect(provider.url, '${ApiConfig.baseUrl}/records/7/photos/11');
      expect(provider.headers?['Authorization'], 'Bearer user-photo-token');
      expect(find.text('OVERLAP 기록 사진'), findsNothing);
    },
  );

  testWidgets(
    'bookmark tap saves only once, never selects map, and can unsave',
    (tester) async {
      var saved = false;
      var saveCalls = 0;
      var deleteCalls = 0;
      var selections = 0;
      final pendingSave = Completer<dynamic>();
      final api = SavedPlacesApi(
        get: (_) async => {
          'place_id': saved ? 77 : null,
          'saved': saved,
          'record_count': 0,
        },
        postKakao: (path, body) {
          saveCalls++;
          expect(path, '/places/kakao/12345/saved');
          expect(body, {
            'name': recommendation.name,
            'address': recommendation.address,
          });
          return pendingSave.future;
        },
        delete: (path) async {
          deleteCalls++;
          expect(path, '/places/77/saved');
          saved = false;
          return {'place_id': 77, 'saved': false, 'saved_count': 0};
        },
      );
      await tester.pumpWidget(card(api, () => selections++));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.bookmark_border));
      await tester.pump();
      expect(saveCalls, 1);
      expect(selections, 0);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(IconButton));
      expect(saveCalls, 1);

      saved = true;
      pendingSave.complete({'place_id': 77, 'saved': true, 'saved_count': 1});
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.bookmark), findsOneWidget);
      await tester.tap(find.byIcon(Icons.bookmark));
      await tester.pumpAndSettle();
      expect(deleteCalls, 1);
      expect(selections, 0);
      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    },
  );

  testWidgets('failed save keeps server state and retries lookup', (
    tester,
  ) async {
    var lookups = 0;
    var selections = 0;
    final api = SavedPlacesApi(
      get: (_) async {
        lookups++;
        return {'place_id': null, 'saved': false, 'record_count': 0};
      },
      postKakao: (_, _) async => throw const ApiException('저장에 실패했어요.'),
    );
    await tester.pumpWidget(card(api, () => selections++));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.bookmark_border));
    await tester.pumpAndSettle();
    expect(find.text('저장에 실패했어요.'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    expect(lookups, 2);
    expect(selections, 0);
  });

  testWidgets('reloading recommendations fetches the bookmark state again', (
    tester,
  ) async {
    var saved = false;
    var lookups = 0;
    final api = SavedPlacesApi(
      get: (_) async {
        lookups++;
        return {
          'place_id': saved ? 77 : null,
          'saved': saved,
          'record_count': 0,
        };
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AiRecommendationContent(
            api: _Recommendations(),
            savedPlacesApi: api,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    saved = true;
    await tester.tap(find.text('다음 장소 추천받기'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    expect(lookups, 2);
  });

  testWidgets(
    'detail changes refresh the card bookmark using shared saved state',
    (tester) async {
      var saved = false;
      final api = SavedPlacesApi(
        get: (path) async {
          expect(path, '/places/kakao/12345');
          return {
            'place_id': saved ? 77 : null,
            'saved': saved,
            'record_count': 0,
          };
        },
        postKakao: (_, _) async {
          saved = true;
          return {'place_id': 77, 'saved': true, 'saved_count': 1};
        },
        delete: (_) async {
          saved = false;
          return {'place_id': 77, 'saved': false, 'saved_count': 0};
        },
      );
      final records = RecordApi(
        tokenProvider: () => 'token',
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({'items': [], 'total': 0}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  AiPlaceRecommendationCard(
                    recommendation: recommendation,
                    savedPlacesApi: api,
                    onTap: () {},
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PlaceDetailScreen(
                          placeId: '',
                          name: recommendation.name,
                          address: recommendation.address,
                          recordCount: 0,
                          recommendation: recommendation,
                          savedPlacesApi: api,
                          recordApi: records,
                        ),
                      ),
                    ),
                    child: const Text('상세 열기'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.bookmark_border));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.bookmark), findsOneWidget);

      await tester.tap(find.text('상세 열기'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.bookmark), findsOneWidget);
      await tester.tap(find.byIcon(Icons.bookmark));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      records.close();
    },
  );
}
