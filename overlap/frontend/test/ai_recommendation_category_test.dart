import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overlap_app/core/network/api_client.dart';
import 'package:overlap_app/features/ai/models/ai_place_recommendation.dart';
import 'package:overlap_app/features/ai/screens/ai_recommendation_screen.dart';
import 'package:overlap_app/features/ai/services/ai_recommendations_api.dart';
import 'package:overlap_app/features/user/services/saved_places_api.dart';

class _QueuedRecommendations extends AiRecommendationsApi {
  int calls = 0;
  final pending = <Completer<List<AiPlaceRecommendation>>>[];

  @override
  Future<List<AiPlaceRecommendation>> load() {
    calls++;
    final request = Completer<List<AiPlaceRecommendation>>();
    pending.add(request);
    return request.future;
  }
}

const _recommendation = AiPlaceRecommendation(
  kakaoPlaceId: 'place-1',
  name: 'Personalized place',
  address: 'Test street',
  latitude: 35.1,
  longitude: 126.9,
  reason: 'Backend provided reason',
  sourceUrl: 'https://place.map.kakao.com/place-1',
  matchedKeywords: ['quiet'],
);

Widget _screen(_QueuedRecommendations api) => MaterialApp(
  home: Scaffold(
    body: AiRecommendationContent(
      api: api,
      showSheetHeader: true,
      savedPlacesApi: SavedPlacesApi(
        get: (_) async => {'place_id': null, 'saved': false, 'record_count': 0},
      ),
    ),
  ),
);

void main() {
  testWidgets('shows one unified list and requests next backend page', (
    tester,
  ) async {
    final api = _QueuedRecommendations();
    await tester.pumpWidget(_screen(api));
    expect(api.calls, 1);
    expect(find.text('Personalized place'), findsNothing);

    api.pending[0].complete([_recommendation]);
    await tester.pumpAndSettle();

    expect(find.text('AI 장소 추천'), findsOneWidget);
    expect(find.text('새롭게 발견할 장소'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('Personalized place'), findsOneWidget);

    await tester.tap(
      find.text('\uB2E4\uC74C \uC7A5\uC18C \uCD94\uCC9C\uBC1B\uAE30'),
    );
    await tester.pump();
    expect(api.calls, 2);
    api.pending[1].complete([_recommendation]);
    await tester.pumpAndSettle();
    expect(find.text('Personalized place'), findsOneWidget);
  });

  testWidgets('empty recommendations show unified guidance', (tester) async {
    final api = _QueuedRecommendations();
    await tester.pumpWidget(_screen(api));
    api.pending[0].complete(const []);
    await tester.pumpAndSettle();

    expect(
      find.text(
        '\uCDE8\uD5A5\uC5D0 \uB9DE\uB294 \uC7A5\uC18C\uB97C \uC544\uC9C1 \uCC3E\uC9C0 \uBABB\uD588\uC5B4\uC694.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('\uBD84\uC57C'), findsNothing);
  });

  testWidgets('authentication failure is not rendered as empty results', (
    tester,
  ) async {
    final api = _QueuedRecommendations();
    await tester.pumpWidget(_screen(api));
    api.pending[0].completeError(
      const ApiException('expired', statusCode: 401),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('\uB85C\uADF8\uC778\uC774 \uB9CC\uB8CC'),
      findsOneWidget,
    );
    expect(
      find.textContaining('\uCDE8\uD5A5\uC5D0 \uB9DE\uB294 \uC7A5\uC18C'),
      findsNothing,
    );
  });

  testWidgets('small viewport layout has no horizontal category scroller', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _QueuedRecommendations();
    await tester.pumpWidget(_screen(api));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is ListView && widget.scrollDirection == Axis.horizontal,
      ),
      findsNothing,
    );
    api.pending[0].complete(const []);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
