import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:overlap_app/features/map/services/kakao_map_local_server.dart';
import 'package:overlap_app/features/map/widgets/kakao_map_webview.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

Future<Map<String, dynamic>> runResolution(String scenario) async {
  final page = KakaoMapLocalServer().debugMapPage('offline-key');
  final script = page.split('<script>')[1].split('var sdkScript')[0];
  final result = await Process.run(
    'node',
    ['-e', _harness],
    environment: {
      'MAP_RESOLUTION_PAYLOAD': jsonEncode({
        'script': script,
        'scenario': scenario,
      }),
    },
  );
  expect(result.exitCode, 0, reason: result.stderr.toString());
  return jsonDecode(result.stdout as String) as Map<String, dynamic>;
}

void main() {
  test('tap and marker movement return nearby real POIs without auto-selecting one', () async {
    final result = await runResolution(r'''
      context.updateSelectionPosition(position); address();
      categories.forEach((q, i) => q.callback(i === 0 ? [poi('123', 35.0004), poi('456', 35.0001)] : [], i === 0 ? 'OK' : 'ZERO_RESULT'));
      keywords[0].callback([], 'ZERO_RESULT');
    ''');
    final resolved = (result['messages'] as List).last as Map;
    expect(resolved['type'], 'placeResolved');
    expect(resolved['place'], isNull);
    expect((resolved['nearbyPlaces'] as List).map((place) => place['id']), [
      '456',
      '123',
    ]);
    expect(resolved['nearbyPlaces'][0]['placeName'], 'Nearby real POI');
    expect(resolved['nearbyPlaces'][0]['roadAddress'], 'POI road address');
    expect(resolved['nearbyPlaces'][0]['latitude'], 35.0001);
    expect(resolved['latitude'], 35.0);
    expect((result['messages'] as List).first['type'], 'locationChanged');
  });
  test(
    'reverse-geocoded building name and address beat a closer adjacent POI',
    () async {
      final result = await runResolution(r'''
      context.resolvePlaceName(position); address(0, 'CGI Center', 'CGI road address', 'CGI lot address');
      categories.forEach((q, i) => q.callback(i === 0 ? [
        poi('9001', 35.0003, 127, 'CGI Center', 'CGI road address', 'CGI lot address'),
        poi('9002', 35.00005, 127, 'Fire Station', 'Fire road address', 'Fire lot address')
      ] : [], i === 0 ? 'OK' : 'ZERO_RESULT'));
      keywords[0].callback([], 'ZERO_RESULT');
    ''');
      final resolved = (result['messages'] as List).single as Map;
      expect(resolved['isAutoMatched'], isTrue);
      expect(resolved['place']['id'], '9001');
      expect(resolved['place']['placeName'], 'CGI Center');
      expect(resolved['place']['latitude'], 35.0003);
      expect(resolved['nearbyPlaces'], isEmpty);
    },
  );
  test(
    'one isolated POI within twelve meters is automatically recognized',
    () async {
      final result = await runResolution(r'''
      context.resolvePlaceName(position); address();
      categories.forEach((q, i) => q.callback(i === 0 ? [poi('9003', 35.00005)] : [], i === 0 ? 'OK' : 'ZERO_RESULT'));
      keywords[0].callback([], 'ZERO_RESULT');
    ''');
      final resolved = (result['messages'] as List).single as Map;
      expect(resolved['isAutoMatched'], isTrue);
      expect(resolved['place']['id'], '9003');
      expect(resolved['nearbyPlaces'], isEmpty);
    },
  );
  test(
    'building-name keyword search finds a place outside category groups',
    () async {
      final result = await runResolution(r'''
      context.resolvePlaceName(position); address();
      categories.forEach(q => q.callback([], 'ZERO_RESULT'));
      keywords[0].callback([poi('789', 35.0002)], 'OK');
    ''');
      expect(result['keywords'], ['Building from reverse geocoding']);
      expect((result['messages'] as List).single['place'], isNull);
      expect(
        (result['messages'] as List).single['nearbyPlaces'].single['id'],
        '789',
      );
      expect(result['searchRadii'], everyElement(200));
    },
  );
  test(
    'failed or empty searches yield address only and never invent a place ID',
    () async {
      final result = await runResolution(r'''
      context.resolvePlaceName(position); address();
      categories.forEach(q => q.callback([], 'ERROR')); keywords[0].callback([], 'ZERO_RESULT');
    ''');
      final resolved = (result['messages'] as List).single;
      expect(resolved['place'], isNull);
      expect(resolved['placeName'], '');
      expect(resolved['roadAddress'], 'Reverse-geocoded road address');
    },
  );
  test('invalid IDs, invalid coordinates and out-of-radius POIs cannot be selected', () async {
    final result = await runResolution(r'''
      context.resolvePlaceName(position); address();
      categories.forEach(q => q.callback([poi('made-up', 35), poi('111', 91), poi('222', 35.01)], 'OK'));
      keywords[0].callback([], 'ZERO_RESULT');
    ''');
    expect((result['messages'] as List).single['place'], isNull);
  });
  test('late resolution from an earlier position is ignored', () async {
    final result = await runResolution(r'''
      context.resolvePlaceName(position);
      const oldAddress = addresses[0]; const oldCategories = categories.slice();
      context.resolvePlaceName(new context.kakao.maps.LatLng(36, 128));
      oldAddress([], 'ZERO_RESULT'); oldCategories.forEach(q => q.callback([poi('111', 35)], 'OK'));
      address(1); categories.slice(oldCategories.length).forEach(q => q.callback([], 'ZERO_RESULT'));
      keywords[0].callback([poi('222', 36, 128)], 'OK');
    ''');
    expect(result['messages'], hasLength(1));
    expect((result['messages'] as List).single['latitude'], 36);
    expect((result['messages'] as List).single['place']['id'], '222');
    expect((result['messages'] as List).single['isAutoMatched'], isTrue);
  });
  test(
    'manual search selection retains its real ID without nearby lookup',
    () async {
      final result = await runResolution(r'''
      context.setSelectionLocation(35, 127, 'Explicit real place', {id: '777', placeName: 'Explicit real place', latitude: 35, longitude: 127, roadAddress: 'Explicit road address', address: ''});
    ''');
      final resolved = (result['messages'] as List).last;
      expect(resolved['place']['id'], '777');
      expect(resolved['place']['roadAddress'], 'Explicit road address');
      expect(resolved['isAutoMatched'], isFalse);
    },
  );
  test(
    'GPS selection reuses resolution and retains the current-location overlay',
    () async {
      final result = await runResolution(r'''
      context.setCurrentLocation({latitude: 35, longitude: 127}); address();
      categories.forEach(q => q.callback([poi('333', 35)], 'OK')); keywords[0].callback([], 'ZERO_RESULT');
    ''');
      expect((result['messages'] as List).last['place']['id'], '333');
      expect((result['messages'] as List).last['isAutoMatched'], isTrue);
      expect(result['currentLocationPins'], 1);
    },
  );
  test('silent SDK callback times out, preserves address, and ignores later results', () async {
    final result = await runResolution(r'''
      context.resolvePlaceName(position); address(); timers[0]();
      categories.forEach(q => q.callback([poi('444', 35)], 'OK')); keywords[0].callback([poi('555', 35)], 'OK');
    ''');
    expect(result['messages'], hasLength(1));
    expect((result['messages'] as List).single['place'], isNull);
    expect(
      (result['messages'] as List).single['roadAddress'],
      'Reverse-geocoded road address',
    );
  });
  testWidgets(
    'WebView bridge validates automatic IDs and forwards manual selection details',
    (tester) async {
      final original = WebViewPlatform.instance;
      final platform = _WebViewPlatform();
      WebViewPlatform.instance = platform;
      const config = MethodChannel('overlap/kakao_config');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        config,
        (_) async => 'offline-key',
      );
      addTearDown(() {
        if (original != null) WebViewPlatform.instance = original;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          config,
          null,
        );
      });
      final selections = <KakaoPlaceSelection>[];
      await tester.pumpWidget(
        MaterialApp(
          home: KakaoMapWebView(
            selectionMode: true,
            localServer: _OfflineServer(),
            onPlaceResolved: selections.add,
            selectionRequest: const KakaoMapSelectionRequest(
              id: 1,
              latitude: 35,
              longitude: 127,
              placeName: 'Manual POI',
              placeId: '777',
              address: 'Manual address',
            ),
          ),
        ),
      );
      await tester.pump();
      platform.navigation.finished!('http://localhost:8080/');
      platform.controller.channel!.onMessageReceived(
        JavaScriptMessage(message: '{"type":"mapReady"}'),
      );
      await tester.pumpAndSettle();
      expect(
        platform.controller.commands
            .where((c) => c.startsWith('setSelectionLocation'))
            .single,
        contains('"id":"777"'),
      );
      final rawPlace = {
        'id': '123',
        'placeName': 'Automatic POI',
        'roadAddress': 'Actual road address',
        'latitude': 35.0001,
        'longitude': 127,
      };
      void send(Object? place) =>
          platform.controller.channel!.onMessageReceived(
            JavaScriptMessage(
              message: jsonEncode({
                'type': 'placeResolved',
                'latitude': 35,
                'longitude': 127,
                'placeName': '',
                'roadAddress': 'Reverse address',
                'place': place,
              }),
            ),
          );
      send(rawPlace);
      expect(selections.last.place!.id, '123');
      expect(selections.last.place!.latitude, 35.0001);
      send({...rawPlace, 'id': 'fake-location-id'});
      expect(selections.last.place, isNull);
      send({...rawPlace, 'latitude': 91});
      expect(selections.last.place, isNull);
      send(null);
      expect(selections.last.place, isNull);
      expect(selections.last.roadAddress, 'Reverse address');
      await tester.pumpWidget(const SizedBox());
    },
  );
}

const _harness = r'''
const vm = require('vm');
const payload = JSON.parse(process.env.MAP_RESOLUTION_PAYLOAD);
const messages = [], addresses = [], categories = [], keywords = [], timers = [], overlays = [];
const context = {
  console: {log() {}}, setTimeout(callback) {timers.push(callback); return timers.length;}, clearTimeout() {},
  document: {getElementById: () => ({}), createElement: () => ({appendChild() {}, addEventListener() {}})},
  OverlapMap: {postMessage: text => messages.push(JSON.parse(text))},
  kakao: {maps: {
    LatLng: function(lat, lng) {this.getLat = () => lat; this.getLng = () => lng;},
    Marker: function(options) {this.position = options.position; this.getPosition = () => this.position; this.setPosition = value => {this.position = value;};},
    event: {addListener() {}},
    CustomOverlay: function(options) {Object.assign(this, options); this.setMap = map => {this.map = map;}; overlays.push(this);},
    services: {Status: {OK: 'OK', ZERO_RESULT: 'ZERO_RESULT', ERROR: 'ERROR'}, SortBy: {DISTANCE: 'DISTANCE'}},
  }},
};
vm.createContext(context); vm.runInContext(payload.script, context);
context.selectionMode = true; context.map = {setCenter() {}, setLevel() {}};
context.geocoder = {coord2Address(x, y, callback) {addresses.push(callback);}};
context.places = {categorySearch(code, callback, options) {categories.push({code, callback, options});}, keywordSearch(keyword, callback, options) {keywords.push({keyword, callback, options});}};
const position = new context.kakao.maps.LatLng(35, 127);
const poi = (id, latitude, longitude = 127, placeName = 'Nearby real POI', roadAddress = 'POI road address', addressName = 'POI lot address') => ({id, place_name: placeName, y: String(latitude), x: String(longitude), road_address_name: roadAddress, address_name: addressName});
const address = (index = 0, buildingName = 'Building from reverse geocoding', roadAddress = 'Reverse-geocoded road address', lotAddress = 'Lot address') => addresses[index]([{road_address: {building_name: buildingName, address_name: roadAddress}, address: {address_name: lotAddress}}], 'OK');
vm.runInNewContext(payload.scenario, {context, position, poi, address, addresses, categories, keywords, timers});
console.log(JSON.stringify({messages, keywords: keywords.map(q => q.keyword), searchRadii: [...keywords, ...categories].map(q => q.options.radius), currentLocationPins: overlays.filter(o => o.map).length}));
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
