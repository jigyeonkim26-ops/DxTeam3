import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:overlap_app/core/network/api_client.dart';
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

Widget card(SavedPlacesApi api, VoidCallback onTap) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(
        width: 280,
        child: AiPlaceRecommendationCard(
          recommendation: recommendation,
          onTap: onTap,
          savedPlacesApi: api,
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('small card shows all text without the image area', (tester) async {
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
    expect(find.byIcon(Icons.auto_awesome), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text(recommendation.name));
    expect(selections, 1);
  });

  testWidgets('bookmark tap saves only once, never selects map, and can unsave', (tester) async {
    var saved = false;
    var saveCalls = 0;
    var deleteCalls = 0;
    var selections = 0;
    final pendingSave = Completer<dynamic>();
    final api = SavedPlacesApi(
      get: (_) async => {
        'place_id': saved ? 77 : null, 'saved': saved, 'record_count': 0,
      },
      postKakao: (path, body) {
        saveCalls++;
        expect(path, '/places/kakao/12345/saved');
        expect(body, {'name': recommendation.name, 'address': recommendation.address});
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
  });

  testWidgets('failed save keeps server state and retries lookup', (tester) async {
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

  testWidgets('reloading recommendations fetches the bookmark state again', (tester) async {
    var saved = false;
    var lookups = 0;
    final api = SavedPlacesApi(get: (_) async {
      lookups++;
      return {'place_id': saved ? 77 : null, 'saved': saved, 'record_count': 0};
    });
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AiRecommendationContent(
      api: _Recommendations(), savedPlacesApi: api,
    ))));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
    saved = true;
    await tester.tap(find.text('다른 장소 추천받기'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bookmark), findsOneWidget);
    expect(lookups, 2);
  });

  testWidgets('detail changes refresh the card bookmark using shared saved state', (tester) async {
    var saved = false;
    final api = SavedPlacesApi(
      get: (path) async {
        expect(path, '/places/kakao/12345');
        return {'place_id': saved ? 77 : null, 'saved': saved, 'record_count': 0};
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
      client: MockClient((request) async => http.Response(
        jsonEncode({'items': [], 'total': 0}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      )),
    );
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: Builder(builder: (context) => Column(children: [
        AiPlaceRecommendationCard(
          recommendation: recommendation,
          savedPlacesApi: api,
          onTap: () {},
        ),
        TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => PlaceDetailScreen(
              placeId: '', name: recommendation.name,
              address: recommendation.address, recordCount: 0,
              recommendation: recommendation,
              savedPlacesApi: api, recordApi: records,
            ),
          )),
          child: const Text('상세 열기'),
        ),
      ])),
    )));
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
  });
}
