import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

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

  @visibleForTesting
  String debugMapPage(String javascriptKey) => _mapHtml(javascriptKey);

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
    .search-marker { border: 0; background: transparent; padding: 0; pointer-events: none; }
    .search-marker__label {
      background: #173f73; border: 2px solid #fff; border-radius: 10px; box-shadow: 0 3px 10px rgba(20, 50, 74, .35);
      color: #fff; display: block; font: 700 13px/1.3 sans-serif; max-width: 220px; padding: 9px 12px; text-align: center;
    }
    .search-marker__pointer { border-left: 8px solid transparent; border-right: 8px solid transparent; border-top: 9px solid #173f73; height: 0; margin: 0 auto; width: 0; }
    .current-location-marker { align-items: center; background: rgba(52, 120, 246, .2); border-radius: 50%; display: flex; height: 34px; justify-content: center; width: 34px; }
    .current-location-marker__dot { background: #3478f6; border: 3px solid #fff; border-radius: 50%; box-shadow: 0 2px 6px rgba(20, 50, 74, .4); height: 16px; width: 16px; }
  </style>
</head>
<body>
  <div id="map"></div>
  <script>
    var mapElement = document.getElementById('map');
    var map;
    var overlays = [];
    var pendingPlaces = [];
    var searchOverlay = null;
    var pendingSearchPlace = null;
    var currentLocationOverlay = null;
    var pendingCurrentLocation = null;

    function escapeHtml(value) {
      return String(value).replace(/[&<>'"]/g, function (character) {
        return ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' })[character];
      });
    }

    function setPlaces(places) {
      pendingPlaces = Array.isArray(places) ? places : [];
      if (!map) return;

      overlays.forEach(function (overlay) { overlay.setMap(null); });
      overlays = [];
      if (!pendingPlaces.length) {
        if (pendingSearchPlace) setSearchPlace(pendingSearchPlace);
        return;
      }

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

      if (pendingSearchPlace) {
        setSearchPlace(pendingSearchPlace);
      } else if (pendingPlaces.length === 1) {
        map.setCenter(bounds.getSouthWest());
      } else {
        map.setBounds(bounds);
      }
    }

    function clearSearchPlace() {
      pendingSearchPlace = null;
      if (searchOverlay) {
        searchOverlay.setMap(null);
        searchOverlay = null;
      }
    }

    function setSearchPlace(place) {
      clearSearchPlace();
      if (!place || !Number.isFinite(Number(place.latitude)) || !Number.isFinite(Number(place.longitude))) {
        return;
      }
      pendingSearchPlace = place;
      if (!map) return;

      var position = new kakao.maps.LatLng(Number(place.latitude), Number(place.longitude));
      var content = document.createElement('div');
      content.className = 'search-marker';
      var label = document.createElement('span');
      label.className = 'search-marker__label';
      label.textContent = '검색 장소 · ' + String(place.name || '');
      var pointer = document.createElement('span');
      pointer.className = 'search-marker__pointer';
      content.appendChild(label);
      content.appendChild(pointer);
      searchOverlay = new kakao.maps.CustomOverlay({ content: content, map: map, position: position, yAnchor: 1 });
      map.setCenter(position);
      map.setLevel(3);
    }

    function setCurrentLocation(location) {
      if (!location || !Number.isFinite(Number(location.latitude)) || !Number.isFinite(Number(location.longitude))) {
        return;
      }
      pendingCurrentLocation = location;
      if (!map) return;

      if (currentLocationOverlay) {
        currentLocationOverlay.setMap(null);
      }
      var position = new kakao.maps.LatLng(Number(location.latitude), Number(location.longitude));
      var content = document.createElement('div');
      content.className = 'current-location-marker';
      var dot = document.createElement('span');
      dot.className = 'current-location-marker__dot';
      content.appendChild(dot);
      currentLocationOverlay = new kakao.maps.CustomOverlay({ content: content, map: map, position: position, yAnchor: 0.5 });
      map.setCenter(position);
      map.setLevel(3);
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
            if (pendingCurrentLocation) setCurrentLocation(pendingCurrentLocation);
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
