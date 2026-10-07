import 'dart:async';
import 'dart:io';

/// Serves the Kakao map page from the exact localhost origin registered in
/// Kakao Developers. It never listens on an external network interface.
class KakaoMapLocalServer {
  HttpServer? _server;

  Future<void> start({required String javascriptKey}) async {
    if (_server != null) {
      return;
    }

    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 8080);
    unawaited(
      _server!.forEach((request) => _handleRequest(request, javascriptKey)),
    );
  }

  Future<void> _handleRequest(HttpRequest request, String javascriptKey) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..write(_mapHtml(javascriptKey));
    await request.response.close();
  }

  Future<void> close() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  String _mapHtml(String javascriptKey) {
    final encodedKey = Uri.encodeQueryComponent(javascriptKey);
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
    .place-marker__pin {
      display: block; height: 48px; position: relative; width: 38px;
    }
    .place-marker__shape {
      display: block; filter: drop-shadow(0 2px 5px rgba(0, 0, 0, .18)); height: 48px; width: 38px;
    }
    .place-marker__shape path {
      fill: var(--pin-color); stroke: #fff; stroke-width: 2;
    }
    .place-marker__count {
      color: #fff; font: 700 14px/1 sans-serif; left: 0; position: absolute; text-align: center; top: 13px; width: 100%;
    }
  </style>
</head>
<body>
  <div id="map"></div>
  <script>
    var mapElement = document.getElementById('map');
    var map;
    var overlays = [];
    var pendingPlaces = [];
    function markerColor(value) {
      if (typeof value !== 'string') return '#14364A';
      var color = value.trim();
      return /^#[0-9a-fA-F]{6}\$/.test(color) ? color : '#14364A';
    }

    function markerCountLabel(value) {
      var count = Number(value);
      if (!Number.isFinite(count) || count < 1) return '0';
      return count >= 10 ? '10+' : String(Math.floor(count));
    }

    function setPlaces(places) {
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
        content.style.setProperty('--pin-color', markerColor(place.groupColorHex));
        content.innerHTML = '<span class="place-marker__pin"><svg class="place-marker__shape" viewBox="0 0 38 48" aria-hidden="true"><path d="M19 1C9.1 1 2 8.3 2 18.2C2 30.4 13.2 42 19 47C24.8 42 36 30.4 36 18.2C36 8.3 28.9 1 19 1Z"/></svg><span class="place-marker__count">' + markerCountLabel(place.recordCount) + '</span></span>';
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
              center: new kakao.maps.LatLng(37.5663, 126.9779),
              level: 5
            });
            setPlaces(pendingPlaces);
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
