import 'package:flutter/foundation.dart';

import '../../../core/network/api_transport.dart';
import '../models/ai_place_recommendation.dart';

typedef RecommendationGet = Future<dynamic> Function(
  String path, {
  Duration? responseTimeout,
});
typedef RecommendationGetWithStatus = Future<dynamic> Function(
  String path, {
  Duration? responseTimeout,
  required void Function(int statusCode) onResponse,
});

class AiRecommendationsApi {
  // Keep the first page in memory for the authenticated session. A newly
  // created screen/API wrapper can then restore it without another request.
  static final Map<String, List<AiPlaceRecommendation>> _firstPages = {};
  static final Map<String, List<List<AiPlaceRecommendation>>> _pagesBySession =
      {};
  static final Map<String, int> _pageIndexes = {};
  static final Map<String, String> _sessionStatuses = {};

  @visibleForTesting
  static void clearSessionCache() {
    _firstPages.clear();
    _pagesBySession.clear();
    _pageIndexes.clear();
    _sessionStatuses.clear();
  }

  AiRecommendationsApi({
    RecommendationGet? get,
    RecommendationGetWithStatus? getWithStatus,
  }) : _get = get ?? ApiTransport.get,
       _cacheAcrossInstances = true,
       _getWithStatus =
           getWithStatus ?? (get == null ? ApiTransport.getWithStatus : null);

  // Sequential provider calls can take up to 156 seconds at their own limits.
  static const _responseTimeout = Duration(seconds: 180);
  static const _endpoint = '/ai/recommendations';
  final RecommendationGet _get;
  final bool _cacheAcrossInstances;
  final RecommendationGetWithStatus? _getWithStatus;
  String? _ownerToken;
  String? _sessionKey;
  bool _loaded = false;
  Future<List<AiPlaceRecommendation>>? _pending;
  String sessionStatus = 'available';
  List<AiPlaceRecommendation> firstRecommendations = const [];
  List<List<AiPlaceRecommendation>> get recommendationPages =>
      _pagesBySession[_sessionKey] ?? const [];
  int get currentPageIndex => _pageIndexes[_sessionKey] ?? 0;

  void selectPage(int index) {
    final pages = recommendationPages;
    if (index < 0 || index >= pages.length) return;
    _pageIndexes[_sessionKey!] = index;
    _loaded = true;
  }

  List<AiPlaceRecommendation> _withoutPreviouslyShownPlaces(
    List<AiPlaceRecommendation> recommendations,
    List<List<AiPlaceRecommendation>> pages,
  ) {
    final seenIds = <String>{};
    final seenNames = <String>{};
    for (final item in pages.expand((page) => page)) {
      final id = item.kakaoPlaceId;
      if (id != null && id.isNotEmpty) seenIds.add(id);
      seenNames.add(item.name.trim().toLowerCase());
    }
    final currentPageIds = <String>{};
    final currentPageNames = <String>{};
    return recommendations
        .where((item) {
          final id = item.kakaoPlaceId;
          final name = item.name.trim().toLowerCase();
          if (id != null && id.isNotEmpty) {
            if (seenIds.contains(id) || !currentPageIds.add(id)) return false;
          } else if (seenNames.contains(name) || !currentPageNames.add(name)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  /// Clears only this account's in-memory pages before an explicitly started
  /// fresh recommendation session. Ordinary replay never calls this method.
  void startNewSession() {
    final key = ApiTransport.sessionIdentity ?? '<anonymous>';
    _firstPages.remove(key);
    _pagesBySession.remove(key);
    _pageIndexes.remove(key);
    _sessionStatuses.remove(key);
    _ownerToken = ApiTransport.sessionIdentity;
    _sessionKey = key;
    _loaded = false;
    _pending = null;
    sessionStatus = 'available';
    firstRecommendations = const [];
  }

  Future<List<AiPlaceRecommendation>> load() {
    final token = ApiTransport.sessionIdentity;
    _sessionKey ??= token ?? '<anonymous>';
    if (_ownerToken == null && token == null) {
      firstRecommendations = _firstPages[_sessionKey] ?? const [];
    }
    if (_ownerToken != token) {
      _ownerToken = token;
      _sessionKey = token ?? '<anonymous>';
      firstRecommendations = _firstPages[_sessionKey] ?? const [];
      _loaded = false;
      _pending = null;
      sessionStatus = 'available';
    }
    if (_cacheAcrossInstances && !_loaded) {
      final cachedPages = _pagesBySession[_sessionKey!];
      if (cachedPages != null && cachedPages.isNotEmpty) {
        _loaded = true;
        sessionStatus = _sessionStatuses[_sessionKey!] ?? 'available';
        final pageIndex = (_pageIndexes[_sessionKey!] ?? 0).clamp(
          0,
          cachedPages.length - 1,
        );
        return Future.value(cachedPages[pageIndex]);
      }
    }
    final inFlight = _pending;
    if (inFlight != null) return inFlight;
    final refresh = _loaded;
    late final Future<List<AiPlaceRecommendation>> request;
    request = _load(refresh: refresh, ownerToken: token).whenComplete(() {
      if (identical(_pending, request)) _pending = null;
    });
    _pending = request;
    return request;
  }

  Future<List<AiPlaceRecommendation>> _load({
    required bool refresh,
    required String? ownerToken,
  }) async {
    final stopwatch = Stopwatch()..start();
    final query = <String, String>{};
    if (refresh) query['refresh'] = 'true';
    final path = query.isEmpty
        ? _endpoint
        : Uri(path: _endpoint, queryParameters: query).toString();
    var httpStatus = 'unknown';
    try {
      final statusAwareGet = _getWithStatus;
      final body = statusAwareGet == null
          ? await _get(path, responseTimeout: _responseTimeout)
          : await statusAwareGet(
              path,
              responseTimeout: _responseTimeout,
              onResponse: (statusCode) => httpStatus = '$statusCode',
            );
      final responseBody = body as Map<String, dynamic>;
      final items =
          responseBody['recommendations'] as List<dynamic>? ?? const [];
      final rawStatus = responseBody['session_status'];
      if (_ownerToken == ownerToken &&
          ApiTransport.sessionIdentity == ownerToken) {
        sessionStatus =
            rawStatus is String &&
                const {'available', 'exhausted', 'empty'}.contains(rawStatus)
            ? rawStatus
            : 'available';
        if (_cacheAcrossInstances) {
          _sessionStatuses[_sessionKey!] = sessionStatus;
        }
      }
      final recommendations = items
          .whereType<Map<String, dynamic>>()
          .map(AiPlaceRecommendation.fromJson)
          .toList();
      var deduplicatedCount = 0;
      if (_ownerToken == ownerToken &&
          ApiTransport.sessionIdentity == ownerToken) {
        _loaded = true;
        if (_cacheAcrossInstances && recommendations.isNotEmpty) {
          final pages = _pagesBySession.putIfAbsent(
            _sessionKey!,
            () => <List<AiPlaceRecommendation>>[],
          );
          // Initial fetch starts a new backend session only when there is no
          // active cached session. Pagination responses append immutable pages.
          if (pages.isEmpty || refresh) {
            final newPage = _withoutPreviouslyShownPlaces(
              recommendations,
              pages,
            );
            deduplicatedCount = recommendations.length - newPage.length;
            if (newPage.isNotEmpty) pages.add(List.unmodifiable(newPage));
            if (pages.isNotEmpty) {
              _pageIndexes[_sessionKey!] = pages.length - 1;
            }
          }
        }
        if (recommendations.isNotEmpty &&
            (_firstPages[_sessionKey!] == null ||
                firstRecommendations.isEmpty)) {
          firstRecommendations = List.unmodifiable(
            _pagesBySession[_sessionKey!]?.first ?? recommendations,
          );
          _firstPages[_sessionKey!] = firstRecommendations;
        }
      }
      if (kDebugMode) {
        debugPrint(
          '[AI recommendations] refresh=$refresh http_status=$httpStatus '
          'raw_item_count=${items.length} parsed_count=${recommendations.length} '
          'deduplicated_count=$deduplicatedCount '
          'cached_page_counts=${(_pagesBySession[_sessionKey] ?? const <List<AiPlaceRecommendation>>[]).map((page) => page.length).join(',')} '
          'current_page_index=${_pageIndexes[_sessionKey] ?? 0} '
          'session_status=$sessionStatus '
          'elapsed_ms=${stopwatch.elapsedMilliseconds}',
        );
      }
      return recommendations;
    } on ApiException catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[AI recommendations] refresh=$refresh http_status=${error.statusCode ?? 'unavailable'} error_kind=${error.kind.name} elapsed_ms=${stopwatch.elapsedMilliseconds}',
        );
      }
      rethrow;
    } catch (error) {
      if (kDebugMode) {
        debugPrint(
          '[AI recommendations] refresh=$refresh http_status=unavailable error_type=${error.runtimeType} elapsed_ms=${stopwatch.elapsedMilliseconds}',
        );
      }
      rethrow;
    }
  }
}
