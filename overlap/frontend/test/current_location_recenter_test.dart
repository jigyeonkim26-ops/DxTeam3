import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overlap_app/features/map/models/current_location.dart';
import 'package:overlap_app/features/map/models/map_search_place.dart';
import 'package:overlap_app/features/map/services/kakao_map_local_server.dart';
import 'package:overlap_app/features/map/widgets/kakao_map_webview.dart';
// The platform interfaces are needed to test the actual WebView bridge.
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

void main() {
  testWidgets(
    'selection map retains repeated GPS requests and coordinate events',
    (tester) async {
      final original = WebViewPlatform.instance;
      final platform = _WebViewPlatform();
      WebViewPlatform.instance = platform;
      const config = MethodChannel('overlap/kakao_config');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        config,
        (_) async => 'test-key',
      );
      addTearDown(() {
        if (original != null) WebViewPlatform.instance = original;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          config,
          null,
        );
      });
      final coordinates = <double>[];
      Widget view(int request) => MaterialApp(
        home: KakaoMapWebView(
          localServer: _OfflineServer(),
          selectionMode: true,
          currentLocation: const CurrentLocation(
            latitude: 35.1,
            longitude: 126.8,
            accuracyMeters: 24,
          ),
          currentLocationRequestId: request,
          onLocationChanged: (latitude, longitude) {
            coordinates.addAll([latitude, longitude]);
          },
        ),
      );
      await tester.pumpWidget(view(1));
      await tester.pump();
      platform.navigation.finished!('http://localhost:8080/');
      platform.controller.channel!.onMessageReceived(
        JavaScriptMessage(message: '{"type":"mapReady"}'),
      );
      await tester.pumpAndSettle();
      platform.controller.channel!.onMessageReceived(
        JavaScriptMessage(
          message:
              '{"type":"locationChanged","latitude":36.25,"longitude":128.5}',
        ),
      );
      expect(coordinates, [36.25, 128.5]);
      await tester.pumpWidget(view(2));
      await tester.pumpAndSettle();
      expect(
        platform.controller.commands.where(
          (c) => c.startsWith('setCurrentLocation'),
        ),
        hasLength(2),
      );
      expect(
        platform.controller.commands.last,
        startsWith('setCurrentLocation'),
      );
      expect(
        platform.controller.commands.any((c) => c.startsWith('setPlaces')),
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'same GPS request recenters A after search B and retains both pins',
    (tester) async {
      final original = WebViewPlatform.instance;
      final platform = _WebViewPlatform();
      WebViewPlatform.instance = platform;
      const config = MethodChannel('overlap/kakao_config');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        config,
        (_) async => 'test-key',
      );
      addTearDown(() {
        if (original != null) WebViewPlatform.instance = original;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          config,
          null,
        );
      });
      const a = CurrentLocation(
        latitude: 35.110713,
        longitude: 126.877803,
        accuracyMeters: 24,
      );
      const b = MapSearchPlace(
        id: 'B',
        name: 'Search B',
        latitude: 37.5663,
        longitude: 126.9779,
      );
      Widget view(int request, MapSearchPlace? search) => MaterialApp(
        home: KakaoMapWebView(
          places: const [],
          localServer: _OfflineServer(),
          searchPlace: search,
          currentLocation: a,
          currentLocationRequestId: request,
          onPlaceTap: (_) {},
        ),
      );
      await tester.pumpWidget(view(1, null));
      // The page spinner remains active until the fake page-finished event.
      await tester.pump();
      platform.navigation.finished!('http://localhost:8080/');
      platform.controller.channel!.onMessageReceived(
        JavaScriptMessage(message: '{"type":"mapReady"}'),
      );
      await tester.pumpAndSettle();
      final controller = platform.controller;
      expect(
        controller.commands.where((c) => c.startsWith('setCurrentLocation')),
        hasLength(1),
      );

      await tester.pumpWidget(view(1, b));
      await tester.pumpAndSettle();
      expect(controller.commands.last, startsWith('setSearchPlace'));

      // A rebuild without a new request must leave search focus alone.
      final count = controller.commands.length;
      await tester.pumpWidget(view(1, b));
      await tester.pumpAndSettle();
      expect(controller.commands, hasLength(count));

      // Equal coordinate values, but a new successful button request.
      await tester.pumpWidget(view(2, b));
      await tester.pumpAndSettle();
      expect(controller.commands.last, startsWith('setCurrentLocation'));
      expect(
        controller.commands.where((c) => c.startsWith('setCurrentLocation')),
        hasLength(2),
      );
      expect(platform.controllersCreated, 1);

      // Execute the commands captured from the real widget against the actual
      // map-page JS, replacing only Kakao/DOM with offline test doubles.
      final page = KakaoMapLocalServer().debugMapPage('test-key');
      final javascript = page.split('<script>')[1].split('var sdkScript')[0];
      final result = await tester.runAsync(
        () => Process.run(
          'node',
          ['-e', _harness],
          // Payload is passed as an argument, never interpolated into shell code.
          environment: {
            'MAP_TEST_PAYLOAD': jsonEncode({
              'script': javascript,
              'commands': controller.commands,
            }),
          },
        ),
      );
      expect(result!.exitCode, 0, reason: '${result.stderr}');
      final state = jsonDecode(result.stdout as String) as Map<String, dynamic>;
      expect(state['centers'], [
        [37.5663, 126.9779],
        [a.latitude, a.longitude],
        [b.latitude, b.longitude],
        [b.latitude, b.longitude],
        [a.latitude, a.longitude],
      ]);
      expect(state['activeCurrentPins'], 1);
      expect(state['activeSearchPins'], 1);
      expect(state['searchPosition'], [b.latitude, b.longitude]);
      expect(state['accuracyRadii'], everyElement(24));
      expect(state['accuracyRadii'], hasLength(2));
      expect(state['boundsCalls'], 0);
      final applied = (state['messages'] as List)
          .where((message) => message['type'] == 'currentLocationApplied')
          .toList();
      expect(applied, hasLength(2));
      expect(applied.last['target'], {
        'latitude': a.latitude,
        'longitude': a.longitude,
      });
      expect(applied.last['center'], {
        'latitude': a.latitude,
        'longitude': a.longitude,
      });
      expect(
        (state['messages'] as List).last['reason'],
        'outsideKakaoKoreaBounds',
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await Future<void>.delayed(Duration.zero);
      });
    },
  );
}

const _harness = r'''
const vm = require('vm');
const payload = JSON.parse(process.env.MAP_TEST_PAYLOAD);
const centers = [], overlays = [], accuracyRadii = [], bounds = [], messages = [];
let mapCenter = {lat: 37.5663, lng: 126.9779};
const context = {
  OverlapMap: {postMessage: message => messages.push(JSON.parse(message))},
  document: {getElementById: () => ({}), createElement: () => ({appendChild() {}, addEventListener() {}, style: {setProperty() {}}})},
  kakao: {maps: {
    LatLng: function(lat, lng) {this.lat = lat; this.lng = lng; this.getLat = () => lat; this.getLng = () => lng;},
    LatLngBounds: function() {this.extend = () => {}; this.getSouthWest = () => ({});},
    Circle: function(options) {Object.assign(this, options); accuracyRadii.push(options.radius); this.setMap = map => {this.map = map;};},
    CustomOverlay: function(options) {
      Object.assign(this, options);
      this.setMap = map => {this.map = map;};
      overlays.push(this);
    },
  }},
};
vm.createContext(context);
vm.runInContext(payload.script, context);
context.map = {setCenter: p => {mapCenter = p; centers.push([p.lat, p.lng]);}, getCenter: () => mapCenter, relayout() {}, setLevel() {}, setBounds: value => bounds.push(value), getLevel: () => 3};
for (const command of payload.commands) vm.runInContext(command, context);
vm.runInContext('setCurrentLocation({latitude:40.7,longitude:-74.0},99)', context);
vm.runInContext('setPlaces([{id:"record-1", recordCount:1, latitude:35, longitude:127, groupColorHex:"#14364A"}])', context);
const active = className => overlays.filter(o => o.map && o.content.className === className);
console.log(JSON.stringify({centers,
  activeCurrentPins: active('current-location-marker').length,
  activeSearchPins: active('search-marker').length,
  searchPosition: [context.searchOverlay.position.lat, context.searchOverlay.position.lng],
  accuracyRadii, boundsCalls: bounds.length, messages,
}));
''';

class _OfflineServer extends KakaoMapLocalServer {
  @override
  Future<void> start({required String javascriptKey}) async {}
  @override
  Future<void> close() async {}
}

class _WebViewPlatform extends WebViewPlatform {
  late _Controller controller;
  late _Navigation navigation;
  int controllersCreated = 0;
  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    controllersCreated++;
    return controller = _Controller(params);
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => navigation = _Navigation(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _Widget(params);
}

class _Controller extends PlatformWebViewController {
  _Controller(super.params) : super.implementation();
  final commands = <String>[];
  JavaScriptChannelParams? channel;
  @override
  Future<void> runJavaScript(String javaScript) async {
    commands.add(javaScript);
  }

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}
  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    channel = params;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {}
  @override
  Future<void> loadRequest(LoadRequestParams params) async {}
}

class _Navigation extends PlatformNavigationDelegate {
  _Navigation(super.params) : super.implementation();
  PageEventCallback? finished;
  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    finished = callback;
  }

  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback callback) async {}
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {}
}

class _Widget extends PlatformWebViewWidget {
  _Widget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox();
}
