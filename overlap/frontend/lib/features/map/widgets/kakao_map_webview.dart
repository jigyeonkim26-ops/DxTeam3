import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/kakao_map_local_server.dart';
import '../models/map_place.dart';

class KakaoPlaceSelection {
  const KakaoPlaceSelection({
    required this.latitude,
    required this.longitude,
    required this.placeName,
    required this.buildingName,
    required this.roadAddress,
    required this.lotAddress,
  });

  final double latitude;
  final double longitude;
  final String placeName;
  final String buildingName;
  final String roadAddress;
  final String lotAddress;
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
  });

  final String keyword;
  final List<KakaoPlaceSearchResult> places;
  final bool isError;
}

class KakaoMapSelectionRequest {
  const KakaoMapSelectionRequest({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.placeName,
  });

  final int id;
  final double latitude;
  final double longitude;
  final String placeName;
}

class KakaoMapWebView extends StatefulWidget {
  const KakaoMapWebView({
    super.key,
    this.places = const [],
    this.onPlaceTap,
    this.selectionMode = false,
    this.initialLatitude = 37.5663,
    this.initialLongitude = 126.9779,
    this.onLocationChanged,
    this.onPlaceResolved,
    this.placeSearchRequest,
    this.onPlaceSearchResults,
    this.selectionRequest,
  });

  final List<MapPlace> places;
  final ValueChanged<MapPlace>? onPlaceTap;
  final bool selectionMode;
  final double initialLatitude;
  final double initialLongitude;
  final void Function(double latitude, double longitude)? onLocationChanged;
  final ValueChanged<KakaoPlaceSelection>? onPlaceResolved;
  final KakaoPlaceSearchRequest? placeSearchRequest;
  final ValueChanged<KakaoPlaceSearchResults>? onPlaceSearchResults;
  final KakaoMapSelectionRequest? selectionRequest;

  @override
  State<KakaoMapWebView> createState() => _KakaoMapWebViewState();
}

class _KakaoMapWebViewState extends State<KakaoMapWebView> {
  static const _configChannel = MethodChannel('overlap/kakao_config');

  final _localServer = KakaoMapLocalServer();
  WebViewController? _controller;
  String? _errorMessage;
  var _isLoading = true;
  var _pageFinished = false;
  KakaoPlaceSearchRequest? _pendingPlaceSearchRequest;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant KakaoMapWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.places, widget.places)) {
      _pushPlacesToMap();
    }
    if (widget.selectionMode &&
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
  }

  Future<void> _initialize() async {
    try {
      final javascriptKey = await _configChannel.invokeMethod<String>(
        'getJavaScriptKey',
      );
      if (javascriptKey == null || javascriptKey.trim().isEmpty) {
        _showError('카카오맵 설정이 필요합니다.');
        return;
      }

      await _localServer.start(javascriptKey: javascriptKey);
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
              if (mounted) {
                setState(() => _isLoading = false);
              }
              _pushPlacesToMap();
              _pushSelectionLocationToMap();
              _pushPlaceSearch();
            },
            onHttpError: (error) => debugPrint(
              'Kakao map HTTP error '
              'url=${_safeUri(error.request?.uri)} '
              'status=${error.response?.statusCode}',
            ),
            onWebResourceError: (error) {
              debugPrint(
                'Kakao map WebView error '
                'mainFrame=${error.isForMainFrame} '
                'url=${_safeUrl(error.url)} '
                'description=${error.description} '
                'type=${error.errorType}',
              );
              if (error.isForMainFrame ?? false) {
                _showError('지도를 불러오지 못했습니다.');
              }
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
            },
          ),
        );

      if (mounted) {
        setState(() => _controller = controller);
        if (_pageFinished) {
          _pushPlacesToMap();
          _pushSelectionLocationToMap();
          _pushPlaceSearch();
        }
      }
    } on PlatformException {
      _showError('카카오맵 설정을 불러오지 못했습니다.');
    } on Exception {
      _showError('지도를 준비하지 못했습니다.');
    }
  }

  void _handleMapMessage(String rawMessage) {
    if (widget.selectionMode) {
      debugPrint('[PLACE_DEBUG] rawMessage: $rawMessage');
      debugPrint('[SEARCH_DEBUG] raw message = $rawMessage');
    }
    final decodedMessage = _decodeMessage(rawMessage);
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
            address: place['address'] is String ? place['address'] as String : '',
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
        ),
      );
      if (widget.selectionMode) {
        debugPrint('[SEARCH_DEBUG] parsed result count = ${searchResults.length}');
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

    final placeId = rawMessage;
    for (final place in widget.places) {
      if (place.id == placeId) {
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

  double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  Future<void> _pushPlacesToMap() async {
    final controller = _controller;
    if (!_pageFinished || controller == null) {
      return;
    }

    final places = widget.places
        .map(
          (place) => {
            'id': place.id,
            'recordCount': place.recordCount,
            'latitude': place.latitude,
            'longitude': place.longitude,
            'groupColorHex': place.groupColorHex,
          },
        )
        .toList();
    try {
      await controller.runJavaScript('setPlaces(${jsonEncode(places)});');
    } on PlatformException {
      _showError('지도를 불러오지 못했습니다.');
    }
  }

  Future<void> _pushSelectionLocationToMap(
    [KakaoMapSelectionRequest? selectionRequest]
  ) async {
    if (!widget.selectionMode) {
      return;
    }

    final controller = _controller;
    if (!_pageFinished || controller == null) {
      return;
    }

    try {
      final latitude = selectionRequest?.latitude ?? widget.initialLatitude;
      final longitude = selectionRequest?.longitude ?? widget.initialLongitude;
      final selectedPlaceName = selectionRequest?.placeName;
      await controller.runJavaScript(
        'setSelectionLocation('
        '$latitude, $longitude, ${jsonEncode(selectedPlaceName)}'
        ');',
      );
    } on PlatformException {
      _showError('지도를 불러오지 못했습니다.');
    }
  }

  Future<void> _pushPlaceSearch() async {
    final searchRequest = _pendingPlaceSearchRequest;
    final controller = _controller;
    if (!_pageFinished || controller == null || searchRequest == null) {
      return;
    }

    try {
      debugPrint('[SEARCH_DEBUG] sending search request to WebView');
      await controller.runJavaScript(
        'searchPlaces('
        '${jsonEncode(searchRequest.keyword)}, '
        '${searchRequest.latitude}, ${searchRequest.longitude}'
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
        ),
      );
    }
  }

  void _showError(String message) {
    if (mounted) {
      setState(() {
        _errorMessage = message;
        _isLoading = false;
      });
    }
  }

  String _safeUrl(String? rawUrl) {
    return _safeUri(Uri.tryParse(rawUrl ?? ''));
  }

  String _safeUri(Uri? uri) {
    if (uri == null || !uri.hasScheme) {
      return 'unknown';
    }
    return uri.replace(query: null, fragment: null).toString();
  }

  @override
  void dispose() {
    _localServer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final errorMessage = _errorMessage;
    if (errorMessage != null) {
      return Center(child: Text(errorMessage));
    }

    final controller = _controller;
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        WebViewWidget(controller: controller),
        if (_isLoading) const Center(child: CircularProgressIndicator()),
      ],
    );
  }
}
