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
    if (_hasLease) return;
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
<html lang="ko"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
html, body, #map { width: 100%; height: 100%; margin: 0; padding: 0; }
.place-marker { border: 0; background: transparent; cursor: pointer; padding: 0; }
.place-marker__pin { display: block; height: 48px; position: relative; width: 38px; }
.place-marker__shape { display: block; filter: drop-shadow(0 2px 5px rgba(0, 0, 0, .18)); height: 48px; width: 38px; }
.place-marker__shape path { fill: var(--pin-color); stroke: #fff; stroke-width: 2; }
.place-marker__count { color: #fff; font: 700 14px/1 sans-serif; left: 0; position: absolute; text-align: center; top: 13px; width: 100%; }
.search-marker { background: transparent; border: 0; padding: 0; pointer-events: none; }
.search-marker__label { background: #173f73; border: 2px solid #fff; border-radius: 10px; box-shadow: 0 3px 10px rgba(20, 50, 74, .35); color: #fff; display: block; font: 700 13px/1.3 sans-serif; max-width: 220px; padding: 9px 12px; text-align: center; }
.search-marker__pointer { border-left: 8px solid transparent; border-right: 8px solid transparent; border-top: 9px solid #173f73; height: 0; margin: 0 auto; width: 0; }
</style></head><body><div id="map"></div><script>
var mapElement = document.getElementById('map');
var map; var overlays = []; var pendingPlaces = [];
var searchOverlay = null; var pendingSearchPlace = null;
var selectionMarker; var selectionMode = $selectionModeLiteral;
var initialSelection = { latitude: $latitude, longitude: $longitude };
function markerColor(value) { if (typeof value !== 'string') return '#14364A'; var color = value.trim(); return /^#[0-9a-fA-F]{6}\$/.test(color) ? color : '#14364A'; }
function markerCountLabel(value) { var count = Number(value); if (!Number.isFinite(count) || count < 1) return '0'; return count >= 10 ? '10+' : String(Math.floor(count)); }
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
function postSelectedLocation(position) { OverlapMap.postMessage(JSON.stringify({ type: 'locationChanged', latitude: position.getLat(), longitude: position.getLng() })); }
function initializeSelectionMarker() {
  var position = new kakao.maps.LatLng(initialSelection.latitude, initialSelection.longitude);
  selectionMarker = new kakao.maps.Marker({ map: map, position: position, draggable: true }); map.setCenter(position);
  kakao.maps.event.addListener(map, 'click', function (event) { selectionMarker.setPosition(event.latLng); postSelectedLocation(event.latLng); });
  kakao.maps.event.addListener(selectionMarker, 'dragend', function () { postSelectedLocation(selectionMarker.getPosition()); }); postSelectedLocation(position);
}
function setSelectionLocation(latitude, longitude) {
  if (!selectionMode) return; initialSelection = { latitude: Number(latitude), longitude: Number(longitude) }; if (!map) return;
  var position = new kakao.maps.LatLng(initialSelection.latitude, initialSelection.longitude); if (selectionMarker) selectionMarker.setPosition(position); map.setCenter(position); postSelectedLocation(position);
}
var sdkScript = document.createElement('script'); sdkScript.src = 'https://dapi.kakao.com/v2/maps/sdk.js?appkey=$encodedKey&autoload=false';
sdkScript.onload = function () {
  if (!window.kakao || !window.kakao.maps) { mapElement.textContent = '지도를 불러오지 못했습니다.'; return; }
  try { kakao.maps.load(function () { try { map = new kakao.maps.Map(mapElement, { center: new kakao.maps.LatLng(initialSelection.latitude, initialSelection.longitude), level: 5 }); if (selectionMode) initializeSelectionMarker(); else setPlaces(pendingPlaces); } catch (error) { mapElement.textContent = '지도를 불러오지 못했습니다.'; } }); } catch (error) { mapElement.textContent = '지도를 불러오지 못했습니다.'; }
};
sdkScript.onerror = function () { mapElement.textContent = '지도를 불러오지 못했습니다.'; }; document.head.appendChild(sdkScript);
</script></body></html>''';
  }
}
