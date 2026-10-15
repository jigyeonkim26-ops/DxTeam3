import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:overlap_app/features/ai/models/ai_place_recommendation.dart';
import 'package:overlap_app/features/ai/services/ai_recommendations_api.dart';
import 'package:overlap_app/features/map/screens/map_screen.dart';
import 'package:overlap_app/features/map/services/map_places_api.dart';
import 'package:overlap_app/features/map/widgets/map_view.dart';
import 'package:overlap_app/features/user/services/saved_places_api.dart';

class _Recommendations extends AiRecommendationsApi {
  @override
  Future<List<AiPlaceRecommendation>> load() async => [
    AiPlaceRecommendation.fromJson({
      'kakao_place_id': '12345',
      'name': '양림동 펭귄마을',
      'address': '광주광역시 남구 양림동',
      'latitude': 35.14,
      'longitude': 126.91,
      'source_url': 'https://place.map.kakao.com/12345',
      'matched_keywords': ['산책'],
      'reason': '조용한 산책 기록과 잘 맞습니다.',
    }),
  ];
}

void main() {
  testWidgets('verified recommendation focuses map and collapses AI sheet', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MapScreen(
            mapPlacesApi: MapPlacesApi(
              request: () async => http.Response('[]', 200),
            ),
            aiRecommendationsApi: _Recommendations(),
            savedPlacesApi: SavedPlacesApi(
              get: (_) async => {
                'place_id': null,
                'saved': false,
                'record_count': 0,
              },
              postKakao: (_, _) async => {
                'place_id': 77,
                'saved': true,
                'saved_count': 1,
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final sheet = tester.widget<DraggableScrollableSheet>(
      find.byType(DraggableScrollableSheet),
    );
    sheet.controller!.jumpTo(0.8);
    await tester.pump();
    expect(find.text('양림동 펭귄마을'), findsOneWidget);
    expect(find.text('광주광역시 남구 양림동'), findsOneWidget);
    expect(find.text('산책'), findsOneWidget);
    expect(find.text('조용한 산책 기록과 잘 맞습니다.'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.bookmark_border));
    await tester.pump();
    expect(tester.widget<MapView>(find.byType(MapView)).searchPlace, isNull);
    expect(sheet.controller!.size, closeTo(0.8, 0.01));

    await tester.tap(find.text('양림동 펭귄마을'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final focused = tester.widget<MapView>(find.byType(MapView)).searchPlace;
    expect(focused?.id, '12345');
    expect(focused?.name, '양림동 펭귄마을');
    expect(focused?.address, '광주광역시 남구 양림동');
    expect(focused?.latitude, 35.14);
    expect(focused?.longitude, 126.91);
    expect(sheet.controller!.size, closeTo(0, 0.01));
    expect(find.byType(MapScreen), findsOneWidget);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('AI 추천 장소'), findsOneWidget);
    expect(find.text('장소 상세 보기'), findsOneWidget);
    expect(find.text('0개의 기록'), findsNothing);

    await tester.tap(find.text('장소 상세 보기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('AI 추천 이유'), findsOneWidget);
    expect(find.text('조용한 산책 기록과 잘 맞습니다.'), findsOneWidget);
    expect(find.text('이 장소에 아직 기록이 없어요.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
