import 'dart:async';
import 'dart:io';

/// Serves the Kakao map page from the exact localhost origin registered in
/// Kakao Developers. It never listens on an external network interface.
class KakaoMapLocalServer {
  static HttpServer? _server;
  static String? _javascriptKey;
  static var _clientCount = 0;

  var _hasLease = false;

  Future<void> start({required String javascriptKey}) async {
    if (_hasLease) {
      return;
    }

    if (_server == null) {
      _javascriptKey = javascriptKey;
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8080);
      unawaited(_server!.forEach(_handleRequest));
    }
    _hasLease = true;
    _clientCount += 1;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final query = request.uri.queryParameters;
    final selectionMode = query['selectionMode'] == 'true';
    final latitude = double.tryParse(query['latitude'] ?? '') ?? 37.5663;
    final longitude = double.tryParse(query['longitude'] ?? '') ?? 126.9779;
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..write(
        _mapHtml(
          _javascriptKey!,
          selectionMode: selectionMode,
          latitude: latitude,
          longitude: longitude,
        ),
      );
    await request.response.close();
  }

  Future<void> close() async {
    if (!_hasLease) return;
    _hasLease = false;
    _clientCount -= 1;
    if (_clientCount > 0) return;

    final server = _server;
    _server = null;
    _javascriptKey = null;
    await server?.close(force: true);
  }

  String _mapHtml(
    String javascriptKey, {
    required bool selectionMode,
    required double latitude,
    required double longitude,
  }) {
    final encodedKey = Uri.encodeQueryComponent(javascriptKey);
    final selectionModeLiteral = selectionMode ? 'true' : 'false';
    return '''<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <style>
    html, body, #map { width: 100%; height: 100%; margin: 0; padding: 0; }
    .place-marker { border: 0; background: transparent; padding: 0; cursor: pointer; }
    .place-marker__label {
      align-items: center; background: #ff6b57; border-radius: 999px; box-shadow: 0 3px 8px rgba(20, 50, 74, .2);
      color: #fff; display: flex; font: 700 13px/1 sans-serif; gap: 4px; padding: 9px 12px;
    }
    .place-marker__label::before { content: '●'; font-size: 12px; }
    .place-marker__pointer { border-left: 7px solid transparent; border-right: 7px solid transparent; border-top: 8px solid #ff6b57; height: 0; margin: 0 auto; width: 0; }
  </style>
</head>
<body>
  <div id="map"></div>
  <script>
    var mapElement = document.getElementById('map');
    var map;
    var overlays = [];
    var pendingPlaces = [];
    var selectionMarker;
    var selectionMode = $selectionModeLiteral;
    var initialSelection = { latitude: $latitude, longitude: $longitude };

    function escapeHtml(value) {
      return String(value).replace(/[&<>'"]/g, function (character) {
        return ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' })[character];
      });
    }

    function setPlaces(places) {
      if (selectionMode) return;
      pendingPlaces = Array.isArray(places) ? places : [];
      if (!map) return;

      overlays.forEach(function (overlay) { overlay.setMap(null); });
      overlays = [];
      if (!pendingPlaces.length) return;

      var bounds = new kakao.maps.LatLngBounds();
      pendingPlaces.forEach(function (place) {
        var position = new kakao.maps.LatLng(place.latitude, place.longitude);
        var content = document.createElement('button');
        content.type = 'button';
        content.className = 'place-marker';
        content.innerHTML = '<span class="place-marker__label">' + escapeHtml(place.name) + ' ' + Number(place.recordCount) + '</span><span class="place-marker__pointer"></span>';
        content.addEventListener('click', function () {
          OverlapMap.postMessage(String(place.id));
        });
        overlays.push(new kakao.maps.CustomOverlay({ content: content, map: map, position: position, yAnchor: 1 }));
        bounds.extend(position);
      });

      if (pendingPlaces.length === 1) {
        map.setCenter(bounds.getSouthWest());
      } else {
        map.setBounds(bounds);
      }
    }

    function postSelectedLocation(position) {
      OverlapMap.postMessage(JSON.stringify({
        type: 'locationChanged',
        latitude: position.getLat(),
        longitude: position.getLng()
      }));
    }

    function initializeSelectionMarker() {
      var position = new kakao.maps.LatLng(
        initialSelection.latitude,
        initialSelection.longitude
      );
      selectionMarker = new kakao.maps.Marker({
        map: map,
        position: position,
        draggable: true
      });
      map.setCenter(position);
      kakao.maps.event.addListener(map, 'click', function (event) {
        selectionMarker.setPosition(event.latLng);
        postSelectedLocation(event.latLng);
      });
      kakao.maps.event.addListener(selectionMarker, 'dragend', function () {
        postSelectedLocation(selectionMarker.getPosition());
      });
      postSelectedLocation(position);
    }

    var sdkScript = document.createElement('script');
    sdkScript.src = 'https://dapi.kakao.com/v2/maps/sdk.js?appkey=$encodedKey&autoload=false';
    sdkScript.onload = function () {
      if (!window.kakao || !window.kakao.maps) {
        mapElement.textContent = '지도를 불러오지 못했습니다.';
        return;
      }

      try {
        kakao.maps.load(function () {
          try {
            map = new kakao.maps.Map(mapElement, {
              center: new kakao.maps.LatLng(initialSelection.latitude, initialSelection.longitude),
              level: 5
            });
            if (selectionMode) {
              initializeSelectionMarker();
            } else {
              setPlaces(pendingPlaces);
            }
          } catch (error) {
            mapElement.textContent = '지도를 불러오지 못했습니다.';
          }
        });
      } catch (error) {
        mapElement.textContent = '지도를 불러오지 못했습니다.';
      }
    };
    sdkScript.onerror = function () {
      mapElement.textContent = '지도를 불러오지 못했습니다.';
    };
    document.head.appendChild(sdkScript);
  </script>
</body>
</html>''';
  }
}
