import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/kakao_map_local_server.dart';
import '../models/current_location.dart';
import '../models/map_place.dart';
import '../models/map_search_place.dart';

class KakaoMapWebView extends StatefulWidget {
  const KakaoMapWebView({
    super.key,
    required this.places,
    required this.searchPlace,
    required this.currentLocation,
    required this.currentLocationRequestId,
    required this.onPlaceTap,
    this.localServer,
  });

  final List<MapPlace> places;
  final MapSearchPlace? searchPlace;
  final CurrentLocation? currentLocation;
  // A successful button request must recenter even when GPS hasn't changed.
  final int currentLocationRequestId;
  final ValueChanged<MapPlace> onPlaceTap;
  @visibleForTesting
  final KakaoMapLocalServer? localServer;

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
          onMessageReceived: (message) => _handlePlaceTap(message.message),
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) {
              _pageFinished = true;
              if (mounted) {
                setState(() => _isLoading = false);
              }
              _syncMapState(
                placesChanged: true,
                searchPlaceChanged: true,
                currentLocationChanged: true,
              );
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
        ..loadRequest(Uri.parse('http://localhost:8080/'));

      if (mounted) {
        setState(() => _controller = controller);
        if (_pageFinished) {
          _syncMapState(
            placesChanged: true,
            searchPlaceChanged: true,
            currentLocationChanged: true,
          );
        }
      }
    } on PlatformException {
      _showError('카카오맵 설정을 불러오지 못했습니다.');
    } on Exception {
      _showError('지도를 준비하지 못했습니다.');
    }
  }

  void _handlePlaceTap(String placeId) {
    for (final place in widget.places) {
      if (place.id == placeId) {
        widget.onPlaceTap(place);
        return;
      }
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
      if (placesChanged) {
        final places = widget.places
            .map(
              (place) => {
                'id': place.id,
                'name': place.name,
                'recordCount': place.recordCount,
                'latitude': place.latitude,
                'longitude': place.longitude,
              },
            )
            .toList();
        await controller.runJavaScript('setPlaces(${jsonEncode(places)});');
      }
      if (!mounted) return;
      if (searchPlaceChanged) {
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
