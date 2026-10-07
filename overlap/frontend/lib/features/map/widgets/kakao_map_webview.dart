import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/kakao_map_local_server.dart';
import '../models/map_place.dart';

class KakaoMapWebView extends StatefulWidget {
  const KakaoMapWebView({
    super.key,
    required this.places,
    required this.onPlaceTap,
  });

  final List<MapPlace> places;
  final ValueChanged<MapPlace> onPlaceTap;

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
          onMessageReceived: (message) => _handlePlaceTap(message.message),
        )
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) {
              _pageFinished = true;
              if (mounted) {
                setState(() => _isLoading = false);
              }
              _pushPlacesToMap();
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
          _pushPlacesToMap();
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
