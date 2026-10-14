import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overlap_app/core/network/api_client.dart';
import 'package:overlap_app/features/ai/models/ai_place_recommendation.dart';
import 'package:overlap_app/features/ai/screens/ai_recommendation_screen.dart';
import 'package:overlap_app/features/ai/services/ai_recommendations_api.dart';
import 'package:overlap_app/features/user/services/saved_places_api.dart';

class _QueuedRecommendations extends AiRecommendationsApi {
  final calls = <String>[];
  final pending = <Completer<List<AiPlaceRecommendation>>>[];

  @override
  Future<List<AiPlaceRecommendation>> load({String category = 'all'}) {
    calls.add(category);
    final request = Completer<List<AiPlaceRecommendation>>();
    pending.add(request);
    return request.future;
  }
}

const _placeA = AiPlaceRecommendation(
  kakaoPlaceId: 'cafe-1',
  name: 'Cafe result',
  address: 'Test street',
  latitude: 35.1,
  longitude: 126.9,
  reason: 'Backend provided reason',
  sourceUrl: 'https://place.map.kakao.com/cafe-1',
  matchedKeywords: ['quiet'],
);
const _oldPlace = AiPlaceRecommendation(
  kakaoPlaceId: 'old-1',
  name: 'Old all result',
  address: 'Test street',
  latitude: 35.1,
  longitude: 126.9,
  reason: 'Backend provided reason',
  sourceUrl: 'https://place.map.kakao.com/old-1',
  matchedKeywords: ['quiet'],
);

Widget _screen(_QueuedRecommendations api) => MaterialApp(
  home: Scaffold(
    body: AiRecommendationContent(
      api: api,
      savedPlacesApi: SavedPlacesApi(
        get: (_) async => {'place_id': null, 'saved': false, 'record_count': 0},
      ),
    ),
  ),
);

void main() {
  testWidgets('category changes clear results and ignore stale responses', (
    tester,
  ) async {
    final api = _QueuedRecommendations();
    await tester.pumpWidget(_screen(api));
    expect(api.calls, ['all']);

    await tester.tap(find.widgetWithText(ChoiceChip, '\uCE74\uD398'));
    await tester.pump();
    expect(api.calls, ['all', 'cafe']);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Cafe result'), findsNothing);

    api.pending[1].complete([_placeA]);
    await tester.pumpAndSettle();
    expect(find.text('Cafe result'), findsOneWidget);

    api.pending[0].complete([_oldPlace]);
    await tester.pumpAndSettle();
    expect(find.text('Cafe result'), findsOneWidget);
    expect(find.text('Old all result'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, '\uCE74\uD398'));
    await tester.pump();
    expect(api.calls, ['all', 'cafe']);

    await tester.tap(
      find.text('\uB2E4\uC74C \uC7A5\uC18C \uCD94\uCC9C\uBC1B\uAE30'),
    );
    await tester.pump();
    expect(api.calls, ['all', 'cafe', 'cafe']);
  });

  testWidgets('empty recommendations show category-specific guidance', (
    tester,
  ) async {
    final api = _QueuedRecommendations();
    await tester.pumpWidget(_screen(api));
    api.pending[0].complete(const []);
    await tester.pumpAndSettle();

    expect(
      find.text(
        '\uC774 \uBD84\uC57C\uC5D0\uC11C \uCDE8\uD5A5\uC5D0 \uB9DE\uB294 \uC7A5\uC18C\uB97C \uC544\uC9C1 \uCC3E\uC9C0 \uBABB\uD588\uC5B4\uC694.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('all six category chips send their matching API category', (
    tester,
  ) async {
    final api = _QueuedRecommendations();
    await tester.pumpWidget(_screen(api));
    api.pending[0].complete(const []);
    await tester.pumpAndSettle();

    const selections = <(String label, String category)>[
      ('\uB9DB\uC9D1', 'food'),
      ('\uC220\uC9D1', 'bar'),
      ('\uCE74\uD398', 'cafe'),
      ('\uC790\uC5F0\uC0B0\uCC45', 'nature'),
      ('\uBB38\uD654\uC2A4\uD3EC\uCE20', 'activity'),
    ];
    for (final (label, category) in selections) {
      await tester.tap(find.widgetWithText(ChoiceChip, label));
      await tester.pump();
      expect(api.calls.last, category);
      api.pending.last.complete(const []);
      await tester.pumpAndSettle();
    }
    expect(api.calls, ['all', 'food', 'bar', 'cafe', 'nature', 'activity']);
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
      find.text(
        '\uB85C\uADF8\uC778\uC774 \uB9CC\uB8CC\uB418\uC5C8\uC5B4\uC694. \uB2E4\uC2DC \uB85C\uADF8\uC778\uD574 \uC8FC\uC138\uC694.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        '\uC774 \uBD84\uC57C\uC5D0\uC11C \uCDE8\uD5A5\uC5D0 \uB9DE\uB294 \uC7A5\uC18C\uB97C \uC544\uC9C1 \uCC3E\uC9C0 \uBABB\uD588\uC5B4\uC694.',
      ),
      findsNothing,
    );
  });

  testWidgets('horizontal category chips fit and scroll on a small viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final api = _QueuedRecommendations();
    await tester.pumpWidget(_screen(api));
    final categories = find.byWidgetPredicate(
      (widget) =>
          widget is ListView && widget.scrollDirection == Axis.horizontal,
    );
    expect(categories, findsOneWidget);
    await tester.drag(categories, const Offset(-500, 0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    api.pending[0].complete(const []);
    await tester.pumpAndSettle();
  });
}
