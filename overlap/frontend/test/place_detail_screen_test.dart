import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:overlap_app/core/constants/app_colors.dart';
import 'package:overlap_app/features/map/screens/place_detail_screen.dart';
import 'package:overlap_app/features/ai/models/ai_place_recommendation.dart';
import 'package:overlap_app/features/memory/screens/record_detail_screen.dart';
import 'package:overlap_app/features/memory/services/record_api.dart';
import 'package:overlap_app/features/memory/widgets/record_card.dart';
import 'package:overlap_app/features/user/services/saved_places_api.dart';

RecordApi responseApi(Map<String, dynamic> page) => RecordApi(
  tokenProvider: () => 'token',
  client: MockClient((request) async {
    expect(request.url.path, '/feed');
    expect(request.url.queryParameters['place_id'], '12');
    return http.Response(
      jsonEncode(page),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }),
);

SavedPlacesApi savedApi({bool saved = false}) => SavedPlacesApi(
  get: (_) async => {'place_id': 12, 'saved': saved, 'saved_count': 0},
);

Widget detail(RecordApi api, {SavedPlacesApi? savedPlacesApi}) => MaterialApp(
  home: PlaceDetailScreen(
    placeId: '12',
    name: '광주실감콘텐츠큐브',
    address: '광주광역시',
    recordCount: 1,
    recordApi: api,
    savedPlacesApi: savedPlacesApi ?? savedApi(),
  ),
);

void main() {
  testWidgets('recorded and AI place details preserve the record comment context', (tester) async {
    final api = responseApi({
      'items': [{
        'id': 1,
        'author': {'id': 7, 'name': '작성자'},
        'place': {
          'id': 12, 'name': '광주실감콘텐츠큐브', 'address': '광주광역시',
          'latitude': 35.1, 'longitude': 126.8,
        },
        'created_at': '2026-10-07T00:00:00Z',
        'content': '모임에서 남긴 기록',
        'emotion': 'good',
        'is_private': false,
        'photo_urls': [],
        'shared_groups': [{'id': 10, 'name': '모임'}],
        'comment_context_group_id': 10,
      }],
      'total': 1,
    });
    await tester.pumpWidget(MaterialApp(home: PlaceDetailScreen(
      placeId: '12', name: '광주실감콘텐츠큐브', address: '광주광역시',
      recordCount: 1, sourceGroupId: '20', recordApi: api,
      savedPlacesApi: savedApi(),
    )));
    await tester.pumpAndSettle();
    tester.widget<RecordCard>(find.byType(RecordCard)).onCommentTap();
    await tester.pumpAndSettle();
    expect(tester.widget<RecordDetailScreen>(find.byType(RecordDetailScreen)).commentGroupId, '20');

    await tester.pumpWidget(const SizedBox());
    final recommendation = AiPlaceRecommendation(
      kakaoPlaceId: '12345', name: '광주실감콘텐츠큐브', address: '광주광역시',
      latitude: 35.1, longitude: 126.8, reason: '기록 취향과 맞는 장소',
      sourceUrl: 'https://place.map.kakao.com/12345', matchedKeywords: const ['산책'],
    );
    await tester.pumpWidget(MaterialApp(home: PlaceDetailScreen(
      placeId: '', name: recommendation.name, address: recommendation.address,
      recordCount: 0, recommendation: recommendation, recordApi: api,
      savedPlacesApi: SavedPlacesApi(
        get: (_) async => {'place_id': 12, 'saved': false, 'record_count': 1},
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.byType(RecordCard), findsOneWidget);
    expect(find.text('AI 추천 이유'), findsOneWidget);
    tester.widget<RecordCard>(find.byType(RecordCard)).onCommentTap();
    await tester.pumpAndSettle();
    expect(tester.widget<RecordDetailScreen>(find.byType(RecordDetailScreen)).commentGroupId, '10');
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets('renders records returned for the selected place', (tester) async {
    final api = responseApi({
      'items': [
        {
          'id': 1,
          'author': {'id': 7, 'name': '작성자'},
          'place': {
            'id': 12,
            'name': '광주실감콘텐츠큐브',
            'address': '광주광역시',
            'latitude': 35.1,
            'longitude': 126.8,
          },
          'created_at': '2026-10-07T00:00:00Z',
          'content': '실제 장소 기록',
          'emotion': 'good',
          'is_private': true,
          'photo_urls': [],
          'shared_groups': [],
        },
      ],
      'total': 1,
    });

    await tester.pumpWidget(detail(api));
    await tester.pumpAndSettle();

    expect(find.byType(RecordCard), findsOneWidget);
    expect(find.text('실제 장소 기록'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets('renders an empty state when the selected place has no records', (
    tester,
  ) async {
    final api = responseApi({'items': [], 'total': 0});

    await tester.pumpWidget(detail(api));
    await tester.pumpAndSettle();

    expect(find.text('이 장소에 아직 기록이 없어요.'), findsOneWidget);
    expect(find.byType(RecordCard), findsNothing);
    final emptyText = tester.widget<Text>(find.text('이 장소에 아직 기록이 없어요.'));
    expect(emptyText.style?.fontSize, 14);
    expect(emptyText.style?.fontWeight, FontWeight.normal);
    expect(emptyText.style?.color, AppColors.muted);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets('loads saved state and updates the bookmark after save and unsave', (
    tester,
  ) async {
    var saved = false;
    final calls = <String>[];
    final placesApi = SavedPlacesApi(
      get: (path) async {
        calls.add('GET $path');
        return {'place_id': 12, 'saved': saved, 'saved_count': saved ? 1 : 0};
      },
      post: (path) async {
        calls.add('POST $path');
        saved = true;
        return {'place_id': 12, 'saved': true, 'saved_count': 1};
      },
      delete: (path) async {
        calls.add('DELETE $path');
        saved = false;
        return {'place_id': 12, 'saved': false, 'saved_count': 0};
      },
    );
    final api = responseApi({'items': [], 'total': 0});

    await tester.pumpWidget(detail(api, savedPlacesApi: placesApi));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);

    await tester.tap(find.byIcon(Icons.bookmark_border));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bookmark), findsOneWidget);

    await tester.tap(find.byIcon(Icons.bookmark));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    expect(calls, [
      'GET /places/12/saved',
      'POST /places/12/saved',
      'DELETE /places/12/saved',
    ]);
    await tester.pumpWidget(const SizedBox());
    api.close();
  });

  testWidgets('AI place shows reason, saves only on bookmark, and restores saved state', (tester) async {
    var saved = false;
    final calls = <String>[];
    final savedPlacesApi = SavedPlacesApi(
      get: (path) async {
        calls.add('GET $path');
        return {'place_id': saved ? 77 : null, 'saved': saved, 'record_count': 0};
      },
      postKakao: (path, body) async {
        calls.add('POST $path');
        expect(body, {'name': '양림동 펭귄마을', 'address': '광주광역시 남구'});
        saved = true;
        return {'place_id': 77, 'saved': true, 'saved_count': 1};
      },
      delete: (path) async {
        calls.add('DELETE $path');
        saved = false;
        return {'place_id': 77, 'saved': false, 'saved_count': 0};
      },
    );
    final recordApi = RecordApi(
      tokenProvider: () => 'token',
      client: MockClient((request) async {
        expect(request.url.queryParameters['place_id'], '77');
        return http.Response(jsonEncode({'items': [], 'total': 0}), 200,
            headers: {'content-type': 'application/json; charset=utf-8'});
      }),
    );
    final recommendation = AiPlaceRecommendation(
      kakaoPlaceId: '12345', name: '양림동 펭귄마을', address: '광주광역시 남구',
      latitude: 35.14, longitude: 126.91, reason: '조용한 산책을 좋아해서 추천해요.',
      sourceUrl: 'https://place.map.kakao.com/12345', matchedKeywords: const ['산책'],
    );
    Widget screen() => MaterialApp(home: PlaceDetailScreen(
      placeId: '', name: recommendation.name, address: recommendation.address,
      recordCount: 0, recommendation: recommendation,
      savedPlacesApi: savedPlacesApi, recordApi: recordApi,
    ));

    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.text('AI 추천 이유'), findsOneWidget);
    expect(find.text('조용한 산책을 좋아해서 추천해요.'), findsOneWidget);
    expect(find.text('산책'), findsOneWidget);
    expect(find.text('기록 0개'), findsNothing);
    expect(find.text('이 장소에 아직 기록이 없어요.'), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    expect(calls, ['GET /places/kakao/12345']);

    await tester.tap(find.byIcon(Icons.bookmark_border));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    expect(calls.last, 'POST /places/kakao/12345/saved');

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(screen());
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    await tester.tap(find.byIcon(Icons.bookmark));
    await tester.pumpAndSettle();
    expect(calls.last, 'DELETE /places/77/saved');
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    recordApi.close();
  });
}
