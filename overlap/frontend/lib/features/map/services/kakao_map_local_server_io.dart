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
    final level = int.tryParse(query['level'] ?? '') ?? 5;
    final minimumBoundsLevel =
        int.tryParse(query['minimumBoundsLevel'] ?? '') ?? 0;
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..write(
        _mapHtml(
          _javascriptKey!,
          selectionMode: selectionMode,
          latitude: latitude,
          longitude: longitude,
          level: level,
          minimumBoundsLevel: minimumBoundsLevel,
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
    level: 5,
    minimumBoundsLevel: 0,
  );

  String _mapHtml(
    String javascriptKey, {
    required bool selectionMode,
    required double latitude,
    required double longitude,
    required int level,
    required int minimumBoundsLevel,
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
.current-location-marker { background: transparent; border: 0; display: flex; height: 24px; justify-content: center; width: 24px; }
.current-location-marker__dot { background: #3478f6; border: 3px solid #fff; border-radius: 50%; box-shadow: 0 2px 6px rgba(20, 50, 74, .4); height: 18px; width: 18px; }
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
    var currentLocationOverlay = null; var currentLocationAccuracyCircle = null;
    var pendingCurrentLocation = null; var hasExplicitCurrentLocation = false;
    var pendingCurrentLocationRequestId = null;
    var selectionMarker;
    var geocoder;
    var places;
    var placesService;
    var pendingPlaceSearch;
    var selectionRequestId = 0;
    var searchRequestId = 0;
    var selectedSearchPlace;
    var poiSearchRadius = 200;
    var poiCategoryCodes = [
      'MT1', 'CS2', 'PS3', 'SC4', 'AC5', 'PK6', 'OL7', 'SW8', 'BK9',
      'CT1', 'AG2', 'PO3', 'AT4', 'AD5', 'FD6', 'CE7', 'HP8', 'PM9'
    ];
    var selectionMode = $selectionModeLiteral;
    var initialSelection = { latitude: $latitude, longitude: $longitude };
    var minimumBoundsLevel = $minimumBoundsLevel;

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
  if (!pendingPlaces.length) {
    if (pendingSearchPlace) setSearchPlace(pendingSearchPlace, !hasExplicitCurrentLocation);
    return;
  }
  var bounds = new kakao.maps.LatLngBounds();
  pendingPlaces.forEach(function (place) {
    var position = new kakao.maps.LatLng(place.latitude, place.longitude);
    var content = document.createElement('button'); content.type = 'button'; content.className = 'place-marker';
    content.style.setProperty('--pin-color', markerColor(place.groupColorHex));
    content.innerHTML = '<span class="place-marker__pin"><svg class="place-marker__shape" viewBox="0 0 38 48" aria-hidden="true"><path d="M19 1C9.1 1 2 8.3 2 18.2C2 30.4 13.2 42 19 47C24.8 42 36 30.4 36 18.2C36 8.3 28.9 1 19 1Z"/></svg><span class="place-marker__count">' + markerCountLabel(place.recordCount) + '</span></span>';
    content.style.setProperty('--pin-fill', markerColor(place.groupColorHex));
    content.addEventListener('click', function () { OverlapMap.postMessage(String(place.id)); });
    overlays.push(new kakao.maps.CustomOverlay({ content: content, map: map, position: position, yAnchor: 1 })); bounds.extend(position);
  });
  if (pendingSearchPlace) setSearchPlace(pendingSearchPlace, !hasExplicitCurrentLocation);
  else if (!hasExplicitCurrentLocation && pendingPlaces.length === 1) map.setCenter(bounds.getSouthWest());
  else if (!hasExplicitCurrentLocation) map.setBounds(bounds);
  if (!pendingSearchPlace && minimumBoundsLevel > 0) map.setLevel(Math.max(map.getLevel(), minimumBoundsLevel));
}
function clearSearchPlace() { pendingSearchPlace = null; if (searchOverlay) { searchOverlay.setMap(null); searchOverlay = null; } }
function relayoutMap() {
  if (!map) return false;
  var center = map.getCenter();
  map.relayout();
  map.setCenter(center);
  return true;
}
function setSearchPlace(place, shouldCenter) {
  if (selectionMode) return;
  if (!place || !Number.isFinite(Number(place.latitude)) || !Number.isFinite(Number(place.longitude))) { clearSearchPlace(); return; }
  pendingSearchPlace = place; if (searchOverlay) searchOverlay.setMap(null); searchOverlay = null; if (!map) return;
  var position = new kakao.maps.LatLng(Number(place.latitude), Number(place.longitude));
  var content = document.createElement('div'); content.className = 'search-marker';
  var label = document.createElement('span'); label.className = 'search-marker__label'; label.textContent = '검색 장소 · ' + String(place.name || '');
  var pointer = document.createElement('span'); pointer.className = 'search-marker__pointer'; content.appendChild(label); content.appendChild(pointer);
  searchOverlay = new kakao.maps.CustomOverlay({ content: content, map: map, position: position, yAnchor: 1 });
  if (shouldCenter !== false) { map.setCenter(position); map.setLevel(3); }
}
    function setCurrentLocation(location, requestId) {
      if (!location || !Number.isFinite(Number(location.latitude)) || !Number.isFinite(Number(location.longitude))) {
        if (typeof OverlapMap !== 'undefined' && requestId != null) OverlapMap.postMessage(JSON.stringify({type: 'currentLocationRejected', requestId: requestId, reason: 'invalidCoordinates'}));
        return;
      }
      if (requestId != null && pendingCurrentLocationRequestId != null &&
          requestId < pendingCurrentLocationRequestId) return;
      var latitude = Number(location.latitude);
      var longitude = Number(location.longitude);
      if (latitude < 33.0 || latitude > 38.8 || longitude < 124.5 || longitude > 132.1) {
        if (typeof OverlapMap !== 'undefined' && requestId != null) OverlapMap.postMessage(JSON.stringify({type: 'currentLocationRejected', requestId: requestId, reason: 'outsideKakaoKoreaBounds'}));
        return;
      }
      pendingCurrentLocation = location;
      pendingCurrentLocationRequestId = requestId;
      if (!map) return;

      try {
      if (currentLocationOverlay) {
        currentLocationOverlay.setMap(null);
      }
      if (currentLocationAccuracyCircle) {
        currentLocationAccuracyCircle.setMap(null);
      }
      var position = new kakao.maps.LatLng(latitude, longitude);
      var accuracy = Number(location.accuracyMeters);
      if (Number.isFinite(accuracy) && accuracy > 0) {
        currentLocationAccuracyCircle = new kakao.maps.Circle({
          center: position,
          radius: Math.max(accuracy, 1),
          strokeWeight: 1,
          strokeColor: '#3478f6',
          strokeOpacity: 0.45,
          strokeStyle: 'solid',
          fillColor: '#3478f6',
          fillOpacity: 0.12,
          map: map
        });
      }
      var content = document.createElement('div');
      content.className = 'current-location-marker';
      var dot = document.createElement('span');
      dot.className = 'current-location-marker__dot';
      content.appendChild(dot);
      currentLocationOverlay = new kakao.maps.CustomOverlay({ content: content, map: map, position: position, yAnchor: 0.5 });
      hasExplicitCurrentLocation = true;
      map.setCenter(position);
      map.setLevel(3);
      if (selectionMode) setSelectionLocation(location.latitude, location.longitude);
      if (typeof OverlapMap !== 'undefined' && requestId != null) OverlapMap.postMessage(JSON.stringify({type: 'currentLocationApplied', requestId: requestId, target: {latitude: latitude, longitude: longitude}, center: {latitude: map.getCenter().getLat(), longitude: map.getCenter().getLng()}, level: map.getLevel()}));
      } catch (error) {
        if (typeof OverlapMap !== 'undefined') OverlapMap.postMessage(JSON.stringify({type: 'mapError', stage: 'current_location_apply', errorType: error && error.name || 'unknown'}));
      }
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

    function resolvePlaceName(position, preferredPlaceName, preferredPlace) {
      if (!selectionMode) return;

      var requestId = ++selectionRequestId;
      var buildingName = '';
      var roadAddress = '';
      var lotAddress = '';
      var addressFinished = !geocoder;
      var pendingSearches = places ? poiCategoryCodes.length : 0;
      var nearbyPlaces = {};
      var explicitPlace = normalizePlace(preferredPlace, true);
      var emitted = false;
      // A failed or silent SDK callback must not leave compose stuck loading.
      var timeout = setTimeout(function () {
        addressFinished = true;
        pendingSearches = 0;
        emitResolvedPlace();
      }, 10000);

      function normalizePlace(place, isExplicit) {
        if (!place) return null;
        var id = textOrEmpty(place.id);
        var name = textOrEmpty(isExplicit ? place.placeName : place.place_name);
        var latitude = Number.parseFloat(isExplicit ? place.latitude : place.y);
        var longitude = Number.parseFloat(isExplicit ? place.longitude : place.x);
        if (!id || !id.split('').every(function (character) {
              return character >= '0' && character <= '9';
            }) || !name ||
            !Number.isFinite(latitude) || Math.abs(latitude) > 90 ||
            !Number.isFinite(longitude) || Math.abs(longitude) > 180) return null;
        var radians = Math.PI / 180;
        var latDelta = (latitude - position.getLat()) * radians;
        var lngDelta = (longitude - position.getLng()) * radians;
        var haversine = Math.sin(latDelta / 2) ** 2 +
            Math.cos(position.getLat() * radians) * Math.cos(latitude * radians) *
            Math.sin(lngDelta / 2) ** 2;
        var distance = 6371000 * 2 * Math.asin(Math.sqrt(Math.min(1, haversine)));
        if (distance > poiSearchRadius) return null;
        return {
          id: id, placeName: name, latitude: latitude, longitude: longitude,
          roadAddress: textOrEmpty(isExplicit ? place.roadAddress : place.road_address_name),
          address: textOrEmpty(isExplicit ? place.address : place.address_name),
          distance: distance
        };
      }

      function collectPlaces(result, status) {
        if (status !== kakao.maps.services.Status.OK || !Array.isArray(result)) return;
        result.forEach(function (place) {
          var candidate = normalizePlace(place, false);
          if (candidate) nearbyPlaces[candidate.id] = candidate;
        });
      }

      function normalizedText(value) {
        return textOrEmpty(value).toLocaleLowerCase().replace(/[ .,·()-]/g, '');
      }

      function findConfidentPlace() {
        var candidates = Object.keys(nearbyPlaces).map(function (id) {
          return nearbyPlaces[id];
        }).sort(function (a, b) { return a.distance - b.distance; });
        if (!candidates.length) return null;

        var normalizedBuilding = normalizedText(buildingName);
        if (normalizedBuilding) {
          var buildingMatches = candidates.filter(function (candidate) {
            if (normalizedText(candidate.placeName) !== normalizedBuilding ||
                candidate.distance > 40) return false;
            var candidateRoad = normalizedText(candidate.roadAddress);
            var candidateLot = normalizedText(candidate.address);
            var reverseRoad = normalizedText(roadAddress);
            var reverseLot = normalizedText(lotAddress);
            var hasComparableAddress = (candidateRoad && reverseRoad) ||
                (candidateLot && reverseLot);
            var addressMatches = (candidateRoad && reverseRoad && candidateRoad === reverseRoad) ||
                (candidateLot && reverseLot && candidateLot === reverseLot);
            return !hasComparableAddress || addressMatches;
          });
          if (buildingMatches.length === 1) return buildingMatches[0];
        }

        // Without matching reverse-geocoded building/address evidence, only a
        // very close isolated result is safe to select automatically.
        var closeCandidates = candidates.filter(function (candidate) {
          return candidate.distance <= 12;
        });
        var runnerUp = candidates.find(function (candidate) {
          return candidate.id !== (closeCandidates[0] && closeCandidates[0].id);
        });
        if (closeCandidates.length === 1 &&
            (!runnerUp || runnerUp.distance >= 45)) return closeCandidates[0];
        return null;
      }

      function emitResolvedPlace() {
        if (emitted || requestId !== selectionRequestId ||
            !addressFinished || pendingSearches > 0) return;
        emitted = true;
        clearTimeout(timeout);
        var autoPlace = explicitPlace ? null : findConfidentPlace();
        var place = explicitPlace || autoPlace;
        var sortedPlaces = Object.keys(nearbyPlaces).map(function (id) {
          return nearbyPlaces[id];
        }).sort(function (a, b) { return a.distance - b.distance; });
        OverlapMap.postMessage(JSON.stringify({
          type: 'placeResolved',
          latitude: position.getLat(), longitude: position.getLng(),
          placeName: place ? place.placeName : '', place: place,
          isAutoMatched: !explicitPlace && autoPlace !== null,
          nearbyPlaces: place ? [] : sortedPlaces.slice(0, 5),
          buildingName: buildingName, roadAddress: roadAddress, lotAddress: lotAddress
        }));
      }

      function searchAddressPlace() {
        // Buildings outside Kakao's category groups can still be found by name/address.
        var keyword = buildingName || roadAddress || lotAddress;
        if (!places || !keyword || explicitPlace) return;
        pendingSearches += 1;
        try {
          places.keywordSearch(keyword, function (result, status) {
            if (emitted || requestId !== selectionRequestId) return;
            collectPlaces(result, status);
            pendingSearches -= 1;
            emitResolvedPlace();
          }, {
            location: position, radius: poiSearchRadius, size: 15,
            sort: kakao.maps.services.SortBy.DISTANCE
          });
        } catch (_) { pendingSearches -= 1; }
      }

      if (explicitPlace) {
        addressFinished = true;
        pendingSearches = 0;
        emitResolvedPlace();
        return;
      }

      if (geocoder) {
        try {
          geocoder.coord2Address(position.getLng(), position.getLat(), function (result, status) {
            if (emitted || requestId !== selectionRequestId) return;
            if (status === kakao.maps.services.Status.OK && result && result.length) {
              var item = result[0] || {};
              var road = item.road_address || {};
              buildingName = textOrEmpty(road.building_name);
              roadAddress = textOrEmpty(road.address_name);
              lotAddress = textOrEmpty((item.address || {}).address_name);
            }
            // Register the extra query before allowing resolution to finish.
            searchAddressPlace();
            addressFinished = true;
            emitResolvedPlace();
          });
        } catch (_) { addressFinished = true; }
      }

      poiCategoryCodes.forEach(function (code) {
        if (!places) return;
        try {
          places.categorySearch(code, function (result, status) {
            if (emitted || requestId !== selectionRequestId) return;
            collectPlaces(result, status);
            pendingSearches -= 1;
            emitResolvedPlace();
          }, {
            location: position, radius: poiSearchRadius, size: 15,
            sort: kakao.maps.services.SortBy.DISTANCE
          });
        } catch (_) { pendingSearches -= 1; }
      });
      emitResolvedPlace();
    }

    function updateSelectionPosition(position, preferredPlaceName, preferredPlace) {
      if (selectionMarker) selectionMarker.setPosition(position);
      else if (map) {
        selectionMarker = new kakao.maps.Marker({map: map, position: position, draggable: true});
        kakao.maps.event.addListener(selectionMarker, 'dragend', function () {
          selectedSearchPlace = null;
          updateSelectionPosition(selectionMarker.getPosition());
        });
      }
      if (selectionMode) {
        console.log(
          '[PLACE_DEBUG] selected:',
          position.getLat(),
          position.getLng()
        );
      }
      postSelectedLocation(position);
      resolvePlaceName(position, preferredPlaceName, preferredPlace);
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
      kakao.maps.event.addListener(map, 'click', function (event) {
        selectedSearchPlace = null;
        updateSelectionPosition(event.latLng);
      });
      kakao.maps.event.addListener(map, 'dragend', function () {
        selectedSearchPlace = null;
        updateSelectionPosition(map.getCenter());
      });
    }

    function setSelectionLocation(latitude, longitude, selectedPlaceName, selectedPlace) {
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
      updateSelectionPosition(position, placeName, selectedPlace);
    }

    var sdkScript = document.createElement('script');
    sdkScript.src = 'https://dapi.kakao.com/v2/maps/sdk.js?appkey=$encodedKey&libraries=services&autoload=false';
    sdkScript.onload = function () {
      if (!window.kakao || !window.kakao.maps) {
        mapElement.textContent = '지도를 불러오지 못했습니다.';
        if (typeof OverlapMap !== 'undefined') OverlapMap.postMessage(JSON.stringify({type: 'mapError', stage: 'sdk_global_missing'}));
        return;
      }

      try {
        kakao.maps.load(function () {
          try {
            map = new kakao.maps.Map(mapElement, {
              center: new kakao.maps.LatLng(initialSelection.latitude, initialSelection.longitude),
              level: $level
            });
            kakao.maps.event.addListener(map, 'tilesloaded', function () {
              var center = map.getCenter();
              if (typeof OverlapMap !== 'undefined') OverlapMap.postMessage(JSON.stringify({type: 'mapTilesLoaded', center: {latitude: center.getLat(), longitude: center.getLng()}, level: map.getLevel()}));
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
            if (pendingCurrentLocation) setCurrentLocation(pendingCurrentLocation, pendingCurrentLocationRequestId);
            if (typeof OverlapMap !== 'undefined') OverlapMap.postMessage(JSON.stringify({type: 'mapReady', center: {latitude: map.getCenter().getLat(), longitude: map.getCenter().getLng()}, level: map.getLevel()}));
          } catch (error) {
            mapElement.textContent = '지도를 불러오지 못했습니다.';
            if (typeof OverlapMap !== 'undefined') OverlapMap.postMessage(JSON.stringify({type: 'mapError', stage: 'map_create', errorType: error && error.name || 'unknown'}));
          }
        });
      } catch (error) {
        mapElement.textContent = '지도를 불러오지 못했습니다.';
        if (typeof OverlapMap !== 'undefined') OverlapMap.postMessage(JSON.stringify({type: 'mapError', stage: 'sdk_load', errorType: error && error.name || 'unknown'}));
      }
    };
    sdkScript.onerror = function () {
      mapElement.textContent = '지도를 불러오지 못했습니다.';
      if (typeof OverlapMap !== 'undefined') OverlapMap.postMessage(JSON.stringify({type: 'mapError', stage: 'sdk_script_network'}));
    };
    document.head.appendChild(sdkScript);
  </script>
</body>
</html>''';
  }
}
