import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/current_location.dart';
import '../models/map_place.dart';
import '../models/map_search_place.dart';
import '../services/kakao_map_local_server.dart';

class KakaoMapWebView extends StatefulWidget {
  const KakaoMapWebView({
    super.key,
    this.places = const [],
    this.searchPlace,
    this.onPlaceTap,
    this.selectionMode = false,
    this.initialLatitude = 37.5663,
    this.initialLongitude = 126.9779,
    this.onLocationChanged,
    this.currentLocation,
    this.currentLocationRequestId = 0,
    this.localServer,
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
  final void Function(double latitude, double longitude)? onLocationChanged;

  @override
  State<KakaoMapWebView> createState() => _KakaoMapWebViewState();
}

class _KakaoMapWebViewState extends State<KakaoMapWebView> {
  static const _configChannel = MethodChannel('overlap/kakao_config');
  late final _localServer = widget.localServer ?? KakaoMapLocalServer();
  WebViewController? _controller;
  String? _errorMessage;
  var _isLoading = true;
  var _pageFinished = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(covariant KakaoMapWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final placesChanged = !listEquals(oldWidget.places, widget.places);
    final searchPlaceChanged = oldWidget.searchPlace != widget.searchPlace;
    final currentLocationChanged =
        oldWidget.currentLocation != widget.currentLocation ||
        oldWidget.currentLocationRequestId != widget.currentLocationRequestId;
    if (placesChanged || searchPlaceChanged || currentLocationChanged) {
      _syncMapState(
        placesChanged: placesChanged,
        searchPlaceChanged: searchPlaceChanged,
        currentLocationChanged: currentLocationChanged,
      );
    }
    if (widget.selectionMode &&
        (oldWidget.initialLatitude != widget.initialLatitude ||
            oldWidget.initialLongitude != widget.initialLongitude)) {
      _pushSelectionLocationToMap();
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
              _syncMapState(
                placesChanged: true,
                searchPlaceChanged: true,
                currentLocationChanged: true,
              );
              _pushSelectionLocationToMap();
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
            },
          ),
        );
      if (mounted) {
        setState(() => _controller = controller);
        if (_pageFinished) {
          _syncMapState(
            placesChanged: true,
            searchPlaceChanged: true,
            currentLocationChanged: true,
          );
          _pushSelectionLocationToMap();
        }
      }
    } on PlatformException {
      _showError('카카오맵 설정을 불러오지 못했습니다.');
    } on Exception {
      _showError('지도를 준비하지 못했습니다.');
    }
  }

  void _handleMapMessage(String rawMessage) {
    final decodedMessage = _decodeMessage(rawMessage);
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

  Future<void> _syncMapState({
    required bool placesChanged,
    required bool searchPlaceChanged,
    required bool currentLocationChanged,
  }) async {
    final controller = _controller;
    if (!mounted || !_pageFinished || controller == null) {
      return;
    }
    try {
      if (placesChanged && !widget.selectionMode) {
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
          'setCurrentLocation(${jsonEncode({'latitude': location.latitude, 'longitude': location.longitude})});',
        );
      }
    } on PlatformException {
      if (mounted) _showError('지도를 불러오지 못했습니다.');
    } on Exception {
      if (mounted) _showError('지도를 불러오지 못했습니다.');
    }
  }

  Future<void> _pushSelectionLocationToMap() async {
    if (!widget.selectionMode) return;
    final controller = _controller;
    if (!_pageFinished || controller == null) return;
    try {
      await controller.runJavaScript(
        'setSelectionLocation(${widget.initialLatitude}, ${widget.initialLongitude});',
      );
    } on PlatformException {
      _showError('지도를 불러오지 못했습니다.');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _isLoading = false;
    });
  }

  String _safeUrl(String? rawUrl) => _safeUri(Uri.tryParse(rawUrl ?? ''));
  String _safeUri(Uri? uri) => uri == null || !uri.hasScheme
      ? 'unknown'
      : uri.replace(query: null, fragment: null).toString();

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
