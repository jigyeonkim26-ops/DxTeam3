import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/current_location.dart';
import '../models/map_place.dart';
import '../models/map_search_place.dart';
import '../services/kakao_map_local_server.dart';

class KakaoPlaceSelection {
  const KakaoPlaceSelection({
    required this.latitude,
    required this.longitude,
    required this.placeName,
    required this.buildingName,
    required this.roadAddress,
    required this.lotAddress,
    this.place,
    this.nearbyPlaces = const [],
    this.isAutoMatched = false,
  });

  final double latitude;
  final double longitude;
  final String placeName;
  final String buildingName;
  final String roadAddress;
  final String lotAddress;
  final KakaoPlaceSearchResult? place;
  final List<KakaoPlaceSearchResult> nearbyPlaces;
  final bool isAutoMatched;
}

class KakaoPlaceSearchRequest {
  const KakaoPlaceSearchRequest({
    required this.id,
    required this.keyword,
    required this.latitude,
    required this.longitude,
  });

  final int id;
  final String keyword;
  final double latitude;
  final double longitude;
}

class KakaoPlaceSearchResult {
  const KakaoPlaceSearchResult({
    required this.id,
    required this.placeName,
    required this.categoryName,
    required this.phone,
    required this.roadAddress,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.distance,
  });

  final String id;
  final String placeName;
  final String categoryName;
  final String phone;
  final String roadAddress;
  final String address;
  final double latitude;
  final double longitude;
  final double? distance;
}

class KakaoPlaceSearchResults {
  const KakaoPlaceSearchResults({
    required this.keyword,
    required this.places,
    required this.isError,
    this.requestId,
  });

  final String keyword;
  final List<KakaoPlaceSearchResult> places;
  final bool isError;
  final int? requestId;
}

class KakaoMapSelectionRequest {
  const KakaoMapSelectionRequest({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.placeName,
    this.placeId,
    this.address,
  });

  final int id;
  final double latitude;
  final double longitude;
  final String placeName;
  final String? placeId;
  final String? address;
}

class KakaoMapWebView extends StatefulWidget {
  const KakaoMapWebView({
    super.key,
    this.places = const [],
    this.searchPlace,
    this.onPlaceTap,
    this.selectionMode = false,
    this.initialLatitude = 37.5663,
    this.initialLongitude = 126.9779,
    this.initialMapLevel = 5,
    this.minimumBoundsLevel = 0,
    this.onLocationChanged,
    this.currentLocation,
    this.currentLocationRequestId = 0,
    this.localServer,
    this.onPlaceResolved,
    this.placeSearchRequest,
    this.onPlaceSearchResults,
    this.selectionRequest,
  });

  final CurrentLocation? currentLocation;
  final int currentLocationRequestId;
  @visibleForTesting
  final KakaoMapLocalServer? localServer;
  final List<MapPlace> places;
  final MapSearchPlace? searchPlace;
  final ValueChanged<MapPlace>? onPlaceTap;
  final bool selectionMode;
  final double initialLatitude;
  final double initialLongitude;
  final int initialMapLevel;
  final int minimumBoundsLevel;
  final void Function(double latitude, double longitude)? onLocationChanged;
  final ValueChanged<KakaoPlaceSelection>? onPlaceResolved;
  final KakaoPlaceSearchRequest? placeSearchRequest;
  final ValueChanged<KakaoPlaceSearchResults>? onPlaceSearchResults;
  final KakaoMapSelectionRequest? selectionRequest;

  @override
  State<KakaoMapWebView> createState() => _KakaoMapWebViewState();
}

class _KakaoMapWebViewState extends State<KakaoMapWebView>
    with WidgetsBindingObserver {
  static const _configChannel = MethodChannel('overlap/kakao_config');
  late final _localServer = widget.localServer ?? KakaoMapLocalServer();
  WebViewController? _controller;
  String? _errorMessage;
  var _isLoading = true;
  var _pageFinished = false;
  var _mapReady = false;
  Size? _lastWebViewSize;
  KakaoPlaceSearchRequest? _pendingPlaceSearchRequest;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pendingPlaceSearchRequest = widget.placeSearchRequest;
    _initialize();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _relayoutMap();
  }

  @override
  void didUpdateWidget(covariant KakaoMapWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final placesChanged = !listEquals(oldWidget.places, widget.places);
    final searchPlaceChanged = oldWidget.searchPlace != widget.searchPlace;
    final currentLocationChanged =
        oldWidget.currentLocation != widget.currentLocation ||
        oldWidget.currentLocationRequestId != widget.currentLocationRequestId;
    if (widget.selectionMode &&
        widget.selectionRequest == null &&
        (oldWidget.initialLatitude != widget.initialLatitude ||
            oldWidget.initialLongitude != widget.initialLongitude)) {
      _pushSelectionLocationToMap();
    }
    final placeSearchRequest = widget.placeSearchRequest;
    if (placeSearchRequest != null &&
        placeSearchRequest.id != oldWidget.placeSearchRequest?.id) {
      _pendingPlaceSearchRequest = placeSearchRequest;
      _pushPlaceSearch();
    }
    final selectionRequest = widget.selectionRequest;
    if (selectionRequest != null &&
        selectionRequest.id != oldWidget.selectionRequest?.id) {
      _pushSelectionLocationToMap(selectionRequest);
    }
    if (placesChanged || searchPlaceChanged || currentLocationChanged) {
      _syncMapState(
        placesChanged: placesChanged,
        searchPlaceChanged: searchPlaceChanged,
        currentLocationChanged: currentLocationChanged,
      );
    }
  }

  Future<void> _initialize() async {
    try {
      final javascriptKey = await _configChannel.invokeMethod<String>(
        'getJavaScriptKey',
      );
      if (!mounted) return;
      if (javascriptKey == null || javascriptKey.trim().isEmpty) {
        _showError('카카오맵 설정이 필요합니다.');
        return;
      }
      await _localServer.start(javascriptKey: javascriptKey);
      if (!mounted) {
        await _localServer.close();
        return;
      }
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..addJavaScriptChannel(
          'OverlapMap',
          onMessageReceived: (message) => _handleMapMessage(message.message),
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) {
              _pageFinished = true;
              if (mounted) setState(() => _isLoading = false);
            },
            onHttpError: (error) => debugPrint(
              'Kakao map HTTP error url=${_safeUri(error.request?.uri)} status=${error.response?.statusCode}',
            ),
            onWebResourceError: (error) {
              debugPrint(
                'Kakao map WebView error mainFrame=${error.isForMainFrame} url=${_safeUrl(error.url)} description=${error.description} type=${error.errorType}',
              );
              if (error.isForMainFrame ?? false) _showError('지도를 불러오지 못했습니다.');
            },
          ),
        )
        ..loadRequest(
          Uri(
            scheme: 'http',
            host: 'localhost',
            port: 8080,
            queryParameters: {
              'selectionMode': widget.selectionMode.toString(),
              'latitude': widget.initialLatitude.toString(),
              'longitude': widget.initialLongitude.toString(),
              'level': widget.initialMapLevel.toString(),
              'minimumBoundsLevel': widget.minimumBoundsLevel.toString(),
            },
          ),
        );
      if (mounted) {
        setState(() => _controller = controller);
        if (kDebugMode) {
          debugPrint(
            '[KAKAO_MAP] webview_controller_created selection=${widget.selectionMode}',
          );
        }
        if (_mapReady) {
          _restoreMapState();
        }
      }
    } on PlatformException {
      _showError('카카오맵 설정을 불러오지 못했습니다.');
    } on Exception {
      _showError('지도를 준비하지 못했습니다.');
    }
  }

  Future<void> _restoreMapState() async {
    if (!_mapReady) return;
    await _pushSelectionLocationToMap(widget.selectionRequest);
    await _syncMapState(
      placesChanged: true,
      searchPlaceChanged: true,
      currentLocationChanged: true,
    );
    _pendingPlaceSearchRequest = widget.placeSearchRequest;
    await _pushPlaceSearch();
  }

  void _handleMapMessage(String rawMessage) {
    if (widget.selectionMode) {
      debugPrint('[PLACE_DEBUG] rawMessage: $rawMessage');
      debugPrint('[SEARCH_DEBUG] raw message = $rawMessage');
    }
    if (!mounted) return;
    final decodedMessage = _decodeMessage(rawMessage);
    if (decodedMessage case {'type': 'mapReady'}) {
      _mapReady = true;
      if (kDebugMode) _debugMapCoordinates('ready', decodedMessage['center']);
      if (mounted) _restoreMapState();
      return;
    }
    if (decodedMessage case {'type': 'mapTilesLoaded'}) {
      if (kDebugMode) {
        _debugMapCoordinates('tiles_loaded', decodedMessage['center']);
        debugPrint('[KAKAO_MAP] tiles loaded level=${decodedMessage['level']}');
      }
      return;
    }
    if (decodedMessage case {'type': 'mapError'}) {
      debugPrint(
        '[KAKAO_MAP] initialization error stage=${decodedMessage['stage']} '
        'type=${decodedMessage['errorType'] ?? 'network'}',
      );
      _showError('Kakao 지도를 불러오지 못했습니다. 연결 상태를 확인하고 다시 시도해주세요.');
      return;
    }
    if (decodedMessage case {
      'type': 'currentLocationApplied',
      'requestId': final int requestId,
    }) {
      if (kDebugMode) {
        debugPrint('[GPS_MAP] WebView applied request_id=$requestId');
        _debugMapCoordinates('location_target', decodedMessage['target']);
        _debugMapCoordinates('map_center', decodedMessage['center']);
        debugPrint('[GPS_MAP] map level=${decodedMessage['level']}');
      }
      return;
    }
    if (decodedMessage case {
      'type': 'currentLocationRejected',
      'requestId': final int requestId,
      'reason': final String reason,
    }) {
      debugPrint(
        '[GPS_MAP] WebView rejected request_id=$requestId reason=$reason',
      );
      return;
    }
    if (decodedMessage case {
      'type': 'searchDebug',
      'message': final String message,
    }) {
      debugPrint('[SEARCH_DEBUG] JS: $message');
      return;
    }
    if (decodedMessage case {
      'type': 'placeSearchResults',
      'keyword': final String keyword,
      'places': final List places,
    }) {
      if (widget.selectionMode) {
        debugPrint('[SEARCH_DEBUG] Flutter received results: ${places.length}');
      }
      final searchResults = <KakaoPlaceSearchResult>[];
      for (final place in places) {
        if (place is! Map<String, dynamic>) continue;
        final latitude = _asDouble(place['latitude']);
        final longitude = _asDouble(place['longitude']);
        final placeName = place['placeName'];
        final id = place['id'];
        if (latitude == null ||
            longitude == null ||
            placeName is! String ||
            id is! String) {
          continue;
        }
        searchResults.add(
          KakaoPlaceSearchResult(
            id: id,
            placeName: placeName,
            categoryName: place['categoryName'] is String
                ? place['categoryName'] as String
                : '',
            phone: place['phone'] is String ? place['phone'] as String : '',
            roadAddress: place['roadAddress'] is String
                ? place['roadAddress'] as String
                : '',
            address: place['address'] is String
                ? place['address'] as String
                : '',
            latitude: latitude,
            longitude: longitude,
            distance: _asDouble(place['distance']),
          ),
        );
      }
      widget.onPlaceSearchResults?.call(
        KakaoPlaceSearchResults(
          keyword: keyword,
          places: searchResults,
          isError: false,
          requestId: _asDouble(decodedMessage['requestId'])?.toInt(),
        ),
      );
      if (widget.selectionMode) {
        debugPrint(
          '[SEARCH_DEBUG] parsed result count = ${searchResults.length}',
        );
      }
      return;
    }
    if (decodedMessage case {
      'type': 'placeSearchError',
      'keyword': final String keyword,
    }) {
      widget.onPlaceSearchResults?.call(
        KakaoPlaceSearchResults(
          keyword: keyword,
          places: const [],
          isError: true,
          requestId: _asDouble(decodedMessage['requestId'])?.toInt(),
        ),
      );
      return;
    }
    if (decodedMessage case {
      'type': 'placeResolved',
      'latitude': final num latitude,
      'longitude': final num longitude,
    }) {
      final placeName = decodedMessage['placeName'];
      final buildingName = decodedMessage['buildingName'];
      final roadAddress = decodedMessage['roadAddress'];
      final lotAddress = decodedMessage['lotAddress'];
      final selection = KakaoPlaceSelection(
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
        placeName: placeName is String ? placeName : '',
        buildingName: buildingName is String ? buildingName : '',
        roadAddress: roadAddress is String ? roadAddress : '',
        lotAddress: lotAddress is String ? lotAddress : '',
        place: _parseResolvedPlace(decodedMessage['place']),
        nearbyPlaces: decodedMessage['nearbyPlaces'] is List
            ? (decodedMessage['nearbyPlaces'] as List)
                  .map(_parseResolvedPlace)
                  .whereType<KakaoPlaceSearchResult>()
                  .toList(growable: false)
            : const [],
        isAutoMatched: decodedMessage['isAutoMatched'] == true,
      );
      if (widget.selectionMode) {
        debugPrint('[PLACE_DEBUG] parsed placeName: ${selection.placeName}');
      }
      widget.onPlaceResolved?.call(selection);
      return;
    }

    if (decodedMessage case {
      'type': 'locationChanged',
      'latitude': final num latitude,
      'longitude': final num longitude,
    }) {
      widget.onLocationChanged?.call(latitude.toDouble(), longitude.toDouble());
      return;
    }
    for (final place in widget.places) {
      if (place.id == rawMessage) {
        widget.onPlaceTap?.call(place);
        return;
      }
    }
  }

  Map<String, dynamic>? _decodeMessage(String rawMessage) {
    try {
      final decoded = jsonDecode(rawMessage);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  KakaoPlaceSearchResult? _parseResolvedPlace(Object? rawPlace) {
    if (rawPlace is! Map<String, dynamic>) return null;
    final id = rawPlace['id'];
    final name = rawPlace['placeName'];
    final latitude = _asDouble(rawPlace['latitude']);
    final longitude = _asDouble(rawPlace['longitude']);
    if (id is! String ||
        !RegExp(r'^\d+$').hasMatch(id) ||
        name is! String ||
        name.trim().isEmpty ||
        latitude == null ||
        longitude == null ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      return null;
    }
    return KakaoPlaceSearchResult(
      id: id,
      placeName: name.trim(),
      categoryName: '',
      phone: '',
      roadAddress: rawPlace['roadAddress'] is String
          ? rawPlace['roadAddress'] as String
          : '',
      address: rawPlace['address'] is String
          ? rawPlace['address'] as String
          : '',
      latitude: latitude,
      longitude: longitude,
      distance: _asDouble(rawPlace['distance']),
    );
  }

  double? _asDouble(Object? value) {
    final number = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    return number != null && number.isFinite ? number : null;
  }

  void _debugMapCoordinates(String label, Object? raw) {
    if (!kDebugMode || raw is! Map) return;
    final latitude = _asDouble(raw['latitude']);
    final longitude = _asDouble(raw['longitude']);
    if (latitude == null || longitude == null) return;
    debugPrint(
      '[KAKAO_MAP] $label lat=${latitude.toStringAsFixed(3)} '
      'lon=${longitude.toStringAsFixed(3)} order=lat_lon',
    );
  }

  Future<void> _syncMapState({
    required bool placesChanged,
    required bool searchPlaceChanged,
    required bool currentLocationChanged,
  }) async {
    final controller = _controller;
    if (!mounted || !_mapReady || controller == null) {
      if (currentLocationChanged && widget.currentLocation != null) {
        debugPrint(
          '[GPS_MAP] delivery deferred page_finished=$_pageFinished '
          'controller_ready=${controller != null} '
          'request_id=${widget.currentLocationRequestId}',
        );
      }
      return;
    }
    try {
      if (currentLocationChanged) await _relayoutMap();
      if (placesChanged && !widget.selectionMode) {
        final places = widget.places
            .map(
              (place) => {
                'id': place.id,
                'recordCount': place.recordCount,
                'latitude': place.latitude,
                'longitude': place.longitude,
                'groupColorHex': place.groupColorHex,
                'groupColorHexes': place.groupColorHexes,
              },
            )
            .toList();
        await controller.runJavaScript('setPlaces(${jsonEncode(places)});');
      }
      if (!mounted) return;
      if (searchPlaceChanged && !widget.selectionMode) {
        final searchPlace = widget.searchPlace;
        final command = searchPlace == null
            ? 'clearSearchPlace();'
            : 'setSearchPlace(${searchPlace.toJsonString()});';
        await controller.runJavaScript(command);
      }
      if (!mounted) return;
      if (currentLocationChanged && widget.currentLocation != null) {
        final location = widget.currentLocation!;
        await controller.runJavaScript(
          'setCurrentLocation('
          '${jsonEncode({'latitude': location.latitude, 'longitude': location.longitude, 'accuracyMeters': location.accuracyMeters})}, '
          '${widget.currentLocationRequestId});',
        );
        debugPrint(
          '[GPS_MAP] delivery sent request_id=${widget.currentLocationRequestId}',
        );
      }
    } on PlatformException catch (error) {
      if (currentLocationChanged) {
        debugPrint(
          '[GPS_MAP] delivery failed request_id=${widget.currentLocationRequestId} '
          'platform_code=${error.code}',
        );
      }
      if (mounted) _showError('지도를 불러오지 못했습니다.');
    } on Exception catch (error) {
      if (currentLocationChanged) {
        debugPrint(
          '[GPS_MAP] delivery failed request_id=${widget.currentLocationRequestId} '
          'type=${error.runtimeType}',
        );
      }
      if (mounted) _showError('지도를 불러오지 못했습니다.');
    }
  }

  Future<void> _relayoutMap() async {
    final controller = _controller;
    if (!mounted || !_mapReady || controller == null) return;
    try {
      await controller.runJavaScript('relayoutMap();');
    } on PlatformException catch (error) {
      debugPrint('[KAKAO_MAP] relayout failed code=${error.code}');
    }
  }

  Future<void> _pushSelectionLocationToMap([
    KakaoMapSelectionRequest? selectionRequest,
  ]) async {
    if (!widget.selectionMode) {
      return;
    }

    final controller = _controller;
    if (!mounted || !_mapReady || controller == null) return;
    try {
      final request = selectionRequest ?? widget.selectionRequest;
      final latitude = request?.latitude ?? widget.initialLatitude;
      final longitude = request?.longitude ?? widget.initialLongitude;
      final selectedPlaceName = request?.placeName;
      final selectedPlace = request?.placeId == null
          ? null
          : {
              'id': request!.placeId,
              'placeName': request.placeName,
              'roadAddress': request.address ?? '',
              'address': request.address ?? '',
              'latitude': latitude,
              'longitude': longitude,
            };
      await controller.runJavaScript(
        'setSelectionLocation('
        '$latitude, $longitude, ${jsonEncode(selectedPlaceName)}, ${jsonEncode(selectedPlace)}'
        ');',
      );
    } on PlatformException {
      _showError('지도를 불러오지 못했습니다.');
    }
  }

  Future<void> _pushPlaceSearch() async {
    final searchRequest = _pendingPlaceSearchRequest;
    final controller = _controller;
    if (!mounted || !_mapReady || controller == null || searchRequest == null) {
      return;
    }

    try {
      debugPrint('[SEARCH_DEBUG] sending search request to WebView');
      await controller.runJavaScript(
        'searchPlaces('
        '${jsonEncode(searchRequest.keyword)}, '
        '${searchRequest.latitude}, ${searchRequest.longitude}, ${searchRequest.id}'
        ');',
      );
      debugPrint('[SEARCH_DEBUG] JS search request sent');
      if (identical(searchRequest, _pendingPlaceSearchRequest)) {
        _pendingPlaceSearchRequest = null;
      }
    } on PlatformException {
      widget.onPlaceSearchResults?.call(
        KakaoPlaceSearchResults(
          keyword: searchRequest.keyword,
          places: const [],
          isError: true,
          requestId: searchRequest.id,
        ),
      );
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _isLoading = false;
    });
  }

  Future<void> _retryInitialize() async {
    if (_isLoading) return;
    setState(() {
      _errorMessage = null;
      _isLoading = true;
      _pageFinished = false;
      _mapReady = false;
      _controller = null;
    });
    await _initialize();
  }

  String _safeUrl(String? rawUrl) => _safeUri(Uri.tryParse(rawUrl ?? ''));
  String _safeUri(Uri? uri) => uri == null || !uri.hasScheme
      ? 'unknown'
      : uri.replace(query: null, fragment: null).toString();

  @override
  void dispose() {
    if (kDebugMode) debugPrint('[KAKAO_MAP] webview_disposed');
    WidgetsBinding.instance.removeObserver(this);
    _localServer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final errorMessage = _errorMessage;
    if (errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(errorMessage, textAlign: TextAlign.center),
            TextButton(
              onPressed: _isLoading ? null : _retryInitialize,
              child: const Text('지도 다시 불러오기'),
            ),
          ],
        ),
      );
    }
    final controller = _controller;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (_lastWebViewSize != size) {
          _lastWebViewSize = size;
          WidgetsBinding.instance.addPostFrameCallback((_) => _relayoutMap());
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            WebViewWidget(controller: controller),
            if (_isLoading) const Center(child: CircularProgressIndicator()),
          ],
        );
      },
    );
  }
}
