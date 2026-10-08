import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Serves the Kakao map page from the exact localhost origin registered in
/// Kakao Developers. It never listens on an external network interface.
class KakaoMapLocalServer {
  static HttpServer? _server;
  static Future<HttpServer>? _startingServer;
  static String? _javascriptKey;
  static var _clientCount = 0;
  var _hasLease = false;

  Future<void> start({required String javascriptKey}) async {
    if (_hasLease) return;
    if (_server == null) {
      _javascriptKey = javascriptKey;
      _startingServer ??= HttpServer.bind(InternetAddress.loopbackIPv4, 8080)
          .then((server) {
            _server = server;
            unawaited(server.forEach(_handleRequest));
            return server;
          });
      try {
        await _startingServer;
      } finally {
        _startingServer = null;
      }
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

  @visibleForTesting
  String debugMapPage(String javascriptKey) => _mapHtml(
    javascriptKey,
    selectionMode: false,
    latitude: 37.5663,
    longitude: 126.9779,
  );

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
    .place-marker__pin {
      display: block; height: 48px; position: relative; width: 38px;
    }
    .place-marker__shape {
      display: block; filter: drop-shadow(0 2px 5px rgba(0, 0, 0, .18)); height: 48px; width: 38px;
    }
    .place-marker__shape path {
      fill: var(--pin-fill, var(--pin-color)); stroke: #fff; stroke-width: 2;
    }
    .place-marker__count {
      color: #fff; font: 700 14px/1 sans-serif; left: 0; position: absolute; text-align: center; top: 13px; width: 100%;
    }
.current-location-marker { align-items: center; background: rgba(52, 120, 246, .2); border-radius: 50%; display: flex; height: 34px; justify-content: center; width: 34px; }
.current-location-marker__dot { background: #3478f6; border: 3px solid #fff; border-radius: 50%; box-shadow: 0 2px 6px rgba(20, 50, 74, .4); height: 16px; width: 16px; }
.search-marker { background: transparent; border: 0; padding: 0; pointer-events: none; }
.search-marker__label { background: #173f73; border: 2px solid #fff; border-radius: 10px; box-shadow: 0 3px 10px rgba(20, 50, 74, .35); color: #fff; display: block; font: 700 13px/1.3 sans-serif; max-width: 220px; padding: 9px 12px; text-align: center; }
.search-marker__pointer { border-left: 8px solid transparent; border-right: 8px solid transparent; border-top: 9px solid #173f73; height: 0; margin: 0 auto; width: 0; }

  </style>
</head>
<body>
  <div id="map"></div>
  <script>
    var mapElement = document.getElementById('map');
    var map;
    var overlays = [];
    var pendingPlaces = [];
    var searchOverlay = null; var pendingSearchPlace = null;
    var currentLocationOverlay = null; var pendingCurrentLocation = null;
    var selectionMarker;
    var geocoder;
    var places;
    var placesService;
    var pendingPlaceSearch;
    var selectionRequestId = 0;
    var searchRequestId = 0;
    var selectedSearchPlace;
    var poiSearchRadius = 200;
    var maximumPoiDistance = 30;
    var poiCategoryCodes = [
      'MT1', 'CS2', 'PS3', 'SC4', 'AC5', 'PK6', 'OL7', 'SW8', 'BK9',
      'CT1', 'AG2', 'PO3', 'AT4', 'AD5', 'FD6', 'CE7', 'HP8', 'PM9'
    ];
    var selectionMode = $selectionModeLiteral;
    var initialSelection = { latitude: $latitude, longitude: $longitude };

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
  if (selectionMode) return;
  pendingPlaces = Array.isArray(places) ? places : [];
  if (!map) return;
  overlays.forEach(function (overlay) { overlay.setMap(null); }); overlays = [];
  if (!pendingPlaces.length) { if (pendingSearchPlace) setSearchPlace(pendingSearchPlace); return; }
  var bounds = new kakao.maps.LatLngBounds();
  pendingPlaces.forEach(function (place) {
    var position = new kakao.maps.LatLng(place.latitude, place.longitude);
    var content = document.createElement('button'); content.type = 'button'; content.className = 'place-marker';
    content.style.setProperty('--pin-color', markerColor(place.groupColorHex));
    content.innerHTML = '<span class="place-marker__pin"><svg class="place-marker__shape" viewBox="0 0 38 48" aria-hidden="true"><path d="M19 1C9.1 1 2 8.3 2 18.2C2 30.4 13.2 42 19 47C24.8 42 36 30.4 36 18.2C36 8.3 28.9 1 19 1Z"/></svg><span class="place-marker__count">' + markerCountLabel(place.recordCount) + '</span></span>';
    var colors = Array.from(new Set((Array.isArray(place.groupColorHexes) && place.groupColorHexes.length ? place.groupColorHexes : [place.groupColorHex]).map(markerColor)));
    var svg = content.querySelector('svg');
    var gradientId = 'pin-gradient-' + overlays.length;
    var stops = colors.map(function(color, index) {
      return '<stop offset="' + (100 * index / colors.length) + '%" stop-color="' + color + '"/><stop offset="' + (100 * (index + 1) / colors.length) + '%" stop-color="' + color + '"/>';
    }).join('');
    svg.insertAdjacentHTML('afterbegin', '<defs><linearGradient id="' + gradientId + '">' + stops + '</linearGradient></defs>');
    content.style.setProperty('--pin-fill', 'url(#' + gradientId + ')');
    content.addEventListener('click', function () { OverlapMap.postMessage(String(place.id)); });
    overlays.push(new kakao.maps.CustomOverlay({ content: content, map: map, position: position, yAnchor: 1 })); bounds.extend(position);
  });
  if (pendingSearchPlace) setSearchPlace(pendingSearchPlace); else if (pendingPlaces.length === 1) map.setCenter(bounds.getSouthWest()); else map.setBounds(bounds);
}
function clearSearchPlace() { pendingSearchPlace = null; if (searchOverlay) { searchOverlay.setMap(null); searchOverlay = null; } }
function setSearchPlace(place) {
  if (selectionMode) return;
  if (!place || !Number.isFinite(Number(place.latitude)) || !Number.isFinite(Number(place.longitude))) { clearSearchPlace(); return; }
  pendingSearchPlace = place; if (searchOverlay) searchOverlay.setMap(null); searchOverlay = null; if (!map) return;
  var position = new kakao.maps.LatLng(Number(place.latitude), Number(place.longitude));
  var content = document.createElement('div'); content.className = 'search-marker';
  var label = document.createElement('span'); label.className = 'search-marker__label'; label.textContent = '검색 장소 · ' + String(place.name || '');
  var pointer = document.createElement('span'); pointer.className = 'search-marker__pointer'; content.appendChild(label); content.appendChild(pointer);
  searchOverlay = new kakao.maps.CustomOverlay({ content: content, map: map, position: position, yAnchor: 1 }); map.setCenter(position); map.setLevel(3);
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
      if (selectionMode) setSelectionLocation(location.latitude, location.longitude);
    }


    function postSelectedLocation(position) {
      OverlapMap.postMessage(JSON.stringify({
        type: 'locationChanged',
        latitude: position.getLat(),
        longitude: position.getLng()
      }));
    }

    function textOrEmpty(value) {
      return typeof value === 'string' ? value.trim() : '';
    }

    function resolvePlaceName(position, preferredPlaceName) {
      if (!selectionMode || !geocoder) return;

      var requestId = ++selectionRequestId;
      var buildingName = '';
      var roadAddress = '';
      var lotAddress = '';
      var addressFinished = false;
      var pendingCategorySearches = places ? poiCategoryCodes.length : 0;
      var nearestPlace;

      function emitResolvedPlace() {
        if (requestId !== selectionRequestId ||
            !addressFinished ||
            pendingCategorySearches > 0) {
          return;
        }

        var poiName = nearestPlace && nearestPlace.distance <= maximumPoiDistance
            ? textOrEmpty(nearestPlace.place_name)
            : '';
        var finalPlaceName = preferredPlaceName || poiName || buildingName || roadAddress || lotAddress || '';
        var payload = {
          type: 'placeResolved',
          latitude: position.getLat(),
          longitude: position.getLng(),
          placeName: finalPlaceName,
          buildingName: buildingName,
          roadAddress: roadAddress,
          lotAddress: lotAddress
        };
        console.log('[PLACE_DEBUG] buildingName:', buildingName);
        console.log('[PLACE_DEBUG] roadAddress:', roadAddress);
        console.log('[PLACE_DEBUG] lotAddress:', lotAddress);
        console.log(
          '[PLACE_DEBUG] nearestPoi:',
          nearestPlace || null
        );
        console.log('[PLACE_DEBUG] finalPlaceName:', finalPlaceName);
        console.log('[PLACE_DEBUG] postMessage:', payload);
        OverlapMap.postMessage(JSON.stringify(payload));
      }

      geocoder.coord2Address(
        position.getLng(),
        position.getLat(),
        function(result, status) {
          if (requestId !== selectionRequestId) return;

          if (status === kakao.maps.services.Status.OK && result && result.length) {
            var item = result[0] || {};
            var roadAddressData = item.road_address || {};
            var addressData = item.address || {};
            buildingName = textOrEmpty(roadAddressData.building_name);
            roadAddress = textOrEmpty(roadAddressData.address_name);
            lotAddress = textOrEmpty(addressData.address_name);
          }
          addressFinished = true;
          emitResolvedPlace();
        }
      );

      poiCategoryCodes.forEach(function(categoryCode) {
        if (!places) return;

        console.log('[PLACE_DEBUG] search start', categoryCode);
        places.categorySearch(
          categoryCode,
          function(result, status) {
            if (requestId !== selectionRequestId) return;

            console.log(
              '[PLACE_DEBUG] category result',
              categoryCode,
              status,
              result ? result.length : 0
            );
            if (status === kakao.maps.services.Status.OK && result && result.length) {
              result.forEach(function(place) {
                var placeName = textOrEmpty(place.place_name);
                var distance = Number.parseFloat(place.distance);
                if (!placeName || !Number.isFinite(distance)) return;
                if (!nearestPlace || distance < nearestPlace.distance) {
                  nearestPlace = { place_name: placeName, distance: distance };
                }
              });
            }
            pendingCategorySearches -= 1;
            emitResolvedPlace();
          },
          {
            location: position,
            radius: poiSearchRadius,
            size: 15,
            sort: kakao.maps.services.SortBy.DISTANCE
          }
        );
      });
    }

    function updateSelectionPosition(position, preferredPlaceName) {
      if (selectionMarker) {
        selectionMarker.setPosition(position);
      }
      if (selectionMode) {
        console.log(
          '[PLACE_DEBUG] selected:',
          position.getLat(),
          position.getLng()
        );
      }
      postSelectedLocation(position);
      resolvePlaceName(position, preferredPlaceName);
    }

    function postPlaceSearchResults(keyword, searchResults, requestId) {
      console.log('[SEARCH_DEBUG] postMessage =', searchResults.length);
      OverlapMap.postMessage(JSON.stringify({
        type: 'placeSearchResults',
        requestId: requestId,
        keyword: keyword,
        places: searchResults
      }));
    }

    function postSearchDebug(message) {
      if (!selectionMode) return;
      OverlapMap.postMessage(JSON.stringify({
        type: 'searchDebug',
        message: message
      }));
    }

    function postPlaceSearchError(keyword, requestId) {
      console.log('[SEARCH_DEBUG] postMessage = error');
      OverlapMap.postMessage(JSON.stringify({
        type: 'placeSearchError',
        requestId: requestId,
        keyword: keyword
      }));
    }

    function searchPlaces(keyword, latitude, longitude, flutterRequestId) {
      var query = textOrEmpty(keyword);
      if (!selectionMode || !query) {
        postPlaceSearchResults(query, [], flutterRequestId);
        return;
      }

      console.log('[SEARCH_DEBUG] keyword =', query);
      console.log('[SEARCH_DEBUG] placesService ready =', Boolean(placesService));
      console.log('[SEARCH_DEBUG] latitude =', latitude);
      console.log('[SEARCH_DEBUG] longitude =', longitude);
      postSearchDebug('keywordSearch start: ' + query);
      postSearchDebug(
        'services=' + Boolean(window.kakao && window.kakao.maps &&
          window.kakao.maps.services) +
        ' placesService=' + Boolean(placesService)
      );
      postSearchDebug('latitude=' + latitude + ' longitude=' + longitude);
      if (!placesService) {
        pendingPlaceSearch = {
          keyword: query,
          latitude: latitude,
          longitude: longitude,
          requestId: flutterRequestId
        };
        postSearchDebug('placesService not ready; search queued');
        return;
      }

      var requestId = ++searchRequestId;
      var options = { size: 15 };
      var parsedLatitude = Number(latitude);
      var parsedLongitude = Number(longitude);
      if (Number.isFinite(parsedLatitude) && Number.isFinite(parsedLongitude)) {
        options.location = new kakao.maps.LatLng(parsedLatitude, parsedLongitude);
        options.sort = kakao.maps.services.SortBy.DISTANCE;
      }
      placesService.keywordSearch(
        query,
        function(result, status) {
          if (requestId !== searchRequestId) return;

          console.log('[SEARCH_DEBUG] status =', status);
          console.log('[SEARCH_DEBUG] result count =', result ? result.length : 0);
          console.log(
            '[SEARCH_DEBUG] first place =',
            result && result.length ? result[0].place_name : ''
          );
          postSearchDebug(
            'status=' + status + ' resultCount=' + (result ? result.length : 0)
          );
          postSearchDebug(
            'firstPlace=' + (result && result.length ? result[0].place_name : '')
          );
          if (status === kakao.maps.services.Status.OK && result) {
            var searchResults = result.slice(0, 15).map(function(place) {
                return {
                  id: place.id,
                  placeName: textOrEmpty(place.place_name),
                  categoryName: textOrEmpty(place.category_name),
                  phone: textOrEmpty(place.phone),
                  roadAddress: textOrEmpty(place.road_address_name),
                  address: textOrEmpty(place.address_name),
                  latitude: Number.parseFloat(place.y),
                  longitude: Number.parseFloat(place.x),
                  distance: Number.parseFloat(place.distance)
                };
              });
            postPlaceSearchResults(query, searchResults, flutterRequestId);
            return;
          }
          if (status === kakao.maps.services.Status.ZERO_RESULT) {
            postPlaceSearchResults(query, [], flutterRequestId);
            return;
          }
          postPlaceSearchError(query, flutterRequestId);
        },
        options
      );
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
        selectedSearchPlace = null;
        updateSelectionPosition(event.latLng);
      });
      kakao.maps.event.addListener(map, 'dragend', function () {
        selectedSearchPlace = null;
        updateSelectionPosition(map.getCenter());
      });
      kakao.maps.event.addListener(selectionMarker, 'dragend', function () {
        selectedSearchPlace = null;
        updateSelectionPosition(selectionMarker.getPosition());
      });
      updateSelectionPosition(position);
    }

    function setSelectionLocation(latitude, longitude, selectedPlaceName) {
      if (!selectionMode) return;

      initialSelection = {
        latitude: Number(latitude),
        longitude: Number(longitude)
      };
      if (!map) return;

      var position = new kakao.maps.LatLng(
        initialSelection.latitude,
        initialSelection.longitude
      );
      var placeName = textOrEmpty(selectedPlaceName);
      selectedSearchPlace = placeName ? {
        latitude: initialSelection.latitude,
        longitude: initialSelection.longitude,
        placeName: placeName
      } : null;
      if (selectedSearchPlace) {
        console.log('[SEARCH_DEBUG] selected place', selectedSearchPlace.placeName);
        console.log(
          '[SEARCH_DEBUG] selected lat/lng',
          selectedSearchPlace.latitude,
          selectedSearchPlace.longitude
        );
      }
      map.setCenter(position);
      updateSelectionPosition(position, placeName);
    }

    var sdkScript = document.createElement('script');
    sdkScript.src = 'https://dapi.kakao.com/v2/maps/sdk.js?appkey=$encodedKey&libraries=services&autoload=false';
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
            if (selectionMode && kakao.maps.services) {
              geocoder = new kakao.maps.services.Geocoder();
              places = new kakao.maps.services.Places();
              placesService = new kakao.maps.services.Places();
              if (pendingPlaceSearch) {
                var queuedSearch = pendingPlaceSearch;
                pendingPlaceSearch = null;
                searchPlaces(
                  queuedSearch.keyword,
                  queuedSearch.latitude,
                  queuedSearch.longitude,
                  queuedSearch.requestId
                );
              }
            }
            if (selectionMode) {
              initializeSelectionMarker();
            } else {
              setPlaces(pendingPlaces);
            }
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
