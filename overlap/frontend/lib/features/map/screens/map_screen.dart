import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/place.dart';
import '../../../core/network/api_client.dart';
import '../../group/services/group_list_store.dart';
import '../../group/services/group_api_service.dart';
import '../../ai/screens/ai_recommendation_screen.dart';
import '../../ai/services/ai_recommendations_api.dart';
import '../../ai/models/ai_place_recommendation.dart';
import '../../user/services/saved_places_api.dart';
import '../../memory/services/record_api.dart';
import '../../memory/screens/record_detail_screen.dart';
import '../../notification/services/notification_api.dart';
import '../models/current_location.dart';
import '../models/map_filter.dart';
import '../models/map_place.dart';
import '../models/map_search_place.dart';
import '../models/nearby_reminder.dart';
import '../widgets/map_filter_sheet.dart';
import '../widgets/map_view.dart';
import '../widgets/nearby_reminder_banner.dart';
import '../widgets/place_preview_sheet.dart';
import '../services/current_location_service.dart';
import '../services/map_places_api.dart';
import '../services/nearby_reminder_api.dart';
import '../services/place_search_api.dart';
import 'place_detail_screen.dart';
import 'place_search_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    this.selectedGroupId,
    this.locationService,
    this.requestedFilters,
    this.mapPlacesApi,
    this.aiRecommendationsApi,
    this.savedPlacesApi,
    this.placeRecordApi,
    this.placeSearchApi,
    this.nearbyReminderService,
    this.markNotificationRead,
  });

  final String? selectedGroupId;
  final CurrentLocationService? locationService;
  final Set<MapFilter>? requestedFilters;
  final MapPlacesApi? mapPlacesApi;
  final AiRecommendationsApi? aiRecommendationsApi;
  final SavedPlacesApi? savedPlacesApi;
  final RecordApi? placeRecordApi;
  final PlaceSearchApi? placeSearchApi;
  final NearbyReminderService? nearbyReminderService;
  final Future<void> Function(int notificationId)? markNotificationRead;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  Set<MapFilter> _selectedFilters = {MapFilter.mine};
  List<MapFilter> _availableFilters = [MapFilter.mine];
  bool _allFilters = true;
  int _loadId = 0;
  MapPlace? _selectedPlace;
  MapSearchPlace? _selectedSearchPlace;
  CurrentLocation? _currentLocation;
  var _currentLocationRequestId = 0;
  var _nearbyReminderRequestId = 0;
  NearbyReminder? _nearbyReminder;
  var _isLocating = false;
  final bool _isSatellite = false;
  double _aiSheetExtent = 0.22;
  final DraggableScrollableController _aiSheetController =
      DraggableScrollableController();
  late final MapPlacesApi _mapPlacesApi;
  List<MapPlace> _places = const [];

  Future<void> _goToCurrentLocation() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);
    try {
      final location =
          await (widget.locationService ??
                  const GeolocatorCurrentLocationService())
              .getCurrentLocation();
      if (!mounted) return;
      if (!location.hasValidCoordinates) {
        _showMessage('현재 위치 좌표를 확인하지 못했습니다. 지도는 그대로 유지됩니다.');
        return;
      }
      if (!location.isWithinKakaoKoreaBounds) {
        if (kDebugMode) {
          debugPrint(
            '[GPS_MAP] location rejected reason=outside_kakao_korea_bounds',
          );
        }
        _showMessage('에뮬레이터 위치가 Kakao 국내 지도 표시 범위 밖입니다. 에뮬레이터 위치를 확인해주세요.');
        return;
      }
      if (kDebugMode) {
        debugPrint(
          '[GPS_MAP] location accepted lat=${location.latitude.toStringAsFixed(3)} '
          'lon=${location.longitude.toStringAsFixed(3)} coordinate_order=lat_lon',
        );
      }
      setState(() {
        _currentLocation = location;
        _currentLocationRequestId++;
        _nearbyReminder = null;
      });
      unawaited(_checkNearbyReminder(location));
      debugPrint(
        '[GPS_MAP] location ready for map request_id=$_currentLocationRequestId '
        'coordinates_valid=${location.hasValidCoordinates}',
      );
    } on CurrentLocationFailure catch (failure) {
      debugPrint(
        '[GPS_MAP] location request failed reason=${failure.reason.name}',
      );
      if (!mounted) return;
      final message = switch (failure.reason) {
        CurrentLocationFailureReason.serviceDisabled => '위치 서비스를 켜주세요.',
        CurrentLocationFailureReason.permissionDenied =>
          '현재 위치를 사용하려면 위치 권한이 필요합니다.',
        CurrentLocationFailureReason.permissionPermanentlyDenied =>
          '위치 권한이 영구적으로 거부되었습니다. 설정에서 허용해주세요.',
        CurrentLocationFailureReason.timeout ||
        CurrentLocationFailureReason.inaccurate ||
        CurrentLocationFailureReason.stale ||
        CurrentLocationFailureReason.unavailable =>
          '현재 위치를 확인하지 못했습니다. 다시 시도해주세요.',
      };
      _showMessage(message);
    } catch (_) {
      debugPrint('[GPS_MAP] location request failed type=unexpected');
      if (mounted) {
        _showMessage('현재 위치를 확인하지 못했습니다. 다시 시도해주세요.');
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _checkNearbyReminder(CurrentLocation location) async {
    final requestId = ++_nearbyReminderRequestId;
    try {
      final reminders =
          await (widget.nearbyReminderService ?? NearbyReminderApi()).check(
            location,
          );
      if (!mounted || requestId != _nearbyReminderRequestId) return;
      setState(() => _nearbyReminder = reminders.firstOrNull);
    } catch (_) {
      // Current-location map movement remains usable when reminder lookup fails.
      debugPrint('[GPS_MAP] nearby reminder lookup failed');
    }
  }

  Future<void> _openNearbyReminder() async {
    final reminder = _nearbyReminder;
    if (reminder == null) return;
    setState(() => _nearbyReminder = null);
    try {
      await (widget.markNotificationRead ?? NotificationApi.read)(
        reminder.notificationId,
      );
    } catch (_) {
      // Opening the user's own record must not depend on a read-state update.
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecordDetailScreen(record: reminder.record),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _mapPlacesApi = widget.mapPlacesApi ?? MapPlacesApi();
    if (widget.requestedFilters != null) {
      _allFilters = false;
      _selectedFilters = Set.of(widget.requestedFilters!);
    } else if (widget.selectedGroupId != null) {
      _allFilters = false;
      _selectedFilters = _filtersForGroupId(widget.selectedGroupId);
    }
    ApiClient.sessionRevision.addListener(_onSessionRevision);
    GroupListStore.groupsListenable.addListener(_onGroupRevision);
    RecordApi.revision.addListener(_onRecordRevision);
    _loadMapPlaces();
  }

  @override
  void dispose() {
    ApiClient.sessionRevision.removeListener(_onSessionRevision);
    GroupListStore.groupsListenable.removeListener(_onGroupRevision);
    RecordApi.revision.removeListener(_onRecordRevision);
    _aiSheetController.dispose();
    super.dispose();
  }

  void _onSessionRevision() {
    setState(() {
      _places = const [];
      _availableFilters = [MapFilter.mine];
      _selectedPlace = null;
      _nearbyReminder = null;
      _nearbyReminderRequestId++;
    });
    _loadMapPlaces();
  }

  void _onGroupRevision() {
    setState(() {
      _availableFilters = [
        MapFilter.mine,
        for (final group in GroupListStore.groups)
          MapFilter.group(
            int.parse(group.id),
            group.name,
            pinColorValue: group.pinColorValue,
          ),
      ];
      if (_allFilters) _selectedFilters = _availableFilters.toSet();
    });
    _loadMapPlaces();
  }

  void _onRecordRevision() {
    _loadMapPlaces();
  }

  void _openAiRecommendations() {
    if (!_aiSheetController.isAttached) return;
    _aiSheetController.animateTo(
      .5,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestedFilters != widget.requestedFilters) {
      setState(() {
        _allFilters =
            widget.requestedFilters == null && widget.selectedGroupId == null;
        _selectedFilters = widget.requestedFilters == null
            ? _filtersForGroupId(widget.selectedGroupId)
            : Set.of(widget.requestedFilters!);
        _selectedPlace = null;
      });
    } else if (oldWidget.selectedGroupId != widget.selectedGroupId) {
      setState(() {
        _allFilters = widget.selectedGroupId == null;
        _selectedFilters = _filtersForGroupId(widget.selectedGroupId);
        _selectedPlace = null;
      });
    }
  }

  Set<MapFilter> _filtersForGroupId(String? groupId) {
    if (groupId == null) return _availableFilters.toSet();
    final id = int.tryParse(groupId);
    return id == null ? {MapFilter.mine} : {MapFilter.group(id, '')};
  }

  List<MapPlace> get _visiblePlaces => _places
      .where((place) => place.filters.any(_selectedFilters.contains))
      .map(
        (place) => place.forSelectedFilters(
          _selectedFilters,
          _availableFilters,
          isAll: _allFilters,
        ),
      )
      .toList();

  Future<void> _loadMapPlaces() async {
    final requestId = ++_loadId;
    final token = ApiClient.sessionIdentity;
    try {
      final places = await _mapPlacesApi.load();
      final groups = await GroupApiService.listGroups();
      if (!mounted ||
          requestId != _loadId ||
          token != ApiClient.sessionIdentity) {
        return;
      }
      setState(() {
        _availableFilters = [
          MapFilter.mine,
          for (final group in groups)
            MapFilter.group(
              group.id,
              group.displayName ?? group.name,
              pinColorValue: group.pinColorValue,
            ),
        ];
        if (_allFilters) _selectedFilters = _availableFilters.toSet();
        _places = places;
      });
    } catch (_) {
      if (!mounted ||
          requestId != _loadId ||
          token != ApiClient.sessionIdentity) {
        return;
      }
      setState(() => _places = const []);
    }
  }

  bool get _areAllFiltersSelected => _allFilters;

  String get _filterLabel {
    if (_areAllFiltersSelected) return '전체';
    if (_selectedFilters.isEmpty) return '기록 필터';
    if (_selectedFilters.length == 1) {
      return _availableFilters
              .where((f) => f == _selectedFilters.single)
              .firstOrNull
              ?.label ??
          '기록 필터';
    }
    return '선택 ${_selectedFilters.length}개';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openFilterSheet() async {
    final filters = await showModalBottomSheet<Set<MapFilter>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MapFilterSheet(
        selectedFilters: _selectedFilters,
        availableFilters: _availableFilters,
      ),
    );

    if (filters != null) {
      setState(() {
        _selectedFilters = filters;
        _allFilters = filters.containsAll(_availableFilters);
        if (_selectedPlace != null &&
            !_visiblePlaces.any((p) => p.id == _selectedPlace!.id)) {
          _selectedPlace = null;
        }
      });
    }
  }

  Future<void> _openPlacePreview(MapPlace place) async {
    setState(() => _selectedPlace = place);
    final selectedGroupIds = _selectedFilters
        .map((filter) => filter.groupId)
        .whereType<int>()
        .toList(growable: false);
    // A map filtered to one group has an unambiguous comment context.  Mixed
    // and all-group map views deliberately preserve no context.
    final sourceGroupId = selectedGroupIds.length == 1
        ? '${selectedGroupIds.single}'
        : null;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => PlacePreviewSheet(
        place: place,
        onViewDetails: () {
          Navigator.pop(sheetContext);
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PlaceDetailScreen(
                placeId: place.id,
                name: place.name,
                address: place.address,
                recordCount: place.recordCount,
                sourceGroupId: sourceGroupId,
              ),
            ),
          );
        },
      ),
    );
    if (mounted) setState(() => _selectedPlace = null);
  }

  Future<void> _openPlaceSearch() async {
    final selectedPlace = await Navigator.of(context).push<Place>(
      MaterialPageRoute<Place>(
        builder: (_) => PlaceSearchScreen(searchApi: widget.placeSearchApi),
      ),
    );
    if (!mounted || selectedPlace == null) return;
    final searchPlace = MapSearchPlace.fromPlace(selectedPlace);
    if (!searchPlace.hasValidCoordinates) {
      _showMessage('선택한 장소의 좌표가 올바르지 않습니다.');
      return;
    }
    await _showPlaceOnMap(selectedPlace);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => PlacePreviewSheet.search(
        searchPlace: searchPlace,
        onViewDetails: () {
          Navigator.pop(sheetContext);
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PlaceDetailScreen(
                placeId: '',
                kakaoPlaceId: selectedPlace.id,
                name: selectedPlace.name,
                address: selectedPlace.address,
                recordCount: 0,
                savedPlacesApi: widget.savedPlacesApi,
                recordApi: widget.placeRecordApi,
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showPlaceOnMap(Place place) async {
    final searchPlace = MapSearchPlace.fromPlace(place);
    if (!searchPlace.hasValidCoordinates) {
      _showMessage('선택한 장소의 좌표가 올바르지 않습니다.');
      return;
    }
    setState(() => _selectedSearchPlace = searchPlace);
    if (_aiSheetController.isAttached) {
      await _aiSheetController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _showRecommendedPlaceOnMap(
    AiPlaceRecommendation recommendation,
  ) async {
    final kakaoId = recommendation.kakaoPlaceId;
    final latitude = recommendation.latitude;
    final longitude = recommendation.longitude;
    if (kakaoId == null || latitude == null || longitude == null) return;
    await _showPlaceOnMap(
      Place(
        id: kakaoId,
        name: recommendation.name,
        address: recommendation.address,
        latitude: latitude,
        longitude: longitude,
      ),
    );
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => PlacePreviewSheet.recommendation(
        recommendation: recommendation,
        onViewDetails: () {
          Navigator.pop(sheetContext);
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PlaceDetailScreen(
                placeId: '',
                kakaoPlaceId: kakaoId,
                name: recommendation.name,
                address: recommendation.address,
                recordCount: 0,
                recommendation: recommendation,
                savedPlacesApi: widget.savedPlacesApi,
                recordApi: widget.placeRecordApi,
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gpsBottom = constraints.maxHeight * _aiSheetExtent + 14;
        final shouldHideGps = _aiSheetExtent >= 0.75;
        final isAiSheetCollapsed = _aiSheetExtent <= .04;
        return Stack(
          fit: StackFit.expand,
          children: [
            MapView(
              isSatellite: _isSatellite,
              places: _visiblePlaces,
              selectedPlaceId: _selectedPlace?.id,
              searchPlace: _selectedSearchPlace,
              currentLocation: _currentLocation,
              currentLocationRequestId: _currentLocationRequestId,
              onPlaceTap: _openPlacePreview,
            ),
            Positioned(
              top: AppSpacing.sm,
              left: AppSpacing.md,
              right: AppSpacing.md,
              child: Row(
                children: [
                  Expanded(child: _SearchButton(onTap: _openPlaceSearch)),
                ],
              ),
            ),
            Positioned(
              top: 68,
              left: AppSpacing.md,
              child: _FilterChip(label: _filterLabel, onTap: _openFilterSheet),
            ),
            if (_nearbyReminder != null)
              Positioned(
                top: 112,
                left: AppSpacing.md,
                right: AppSpacing.md,
                child: NearbyReminderBanner(
                  reminder: _nearbyReminder!,
                  onTap: _openNearbyReminder,
                  onDismiss: () => setState(() => _nearbyReminder = null),
                ),
              ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 120),
              right: AppSpacing.md,
              bottom: gpsBottom,
              child: IgnorePointer(
                ignoring: shouldHideGps,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: shouldHideGps ? 0 : 1,
                  child: _RoundIconButton(
                    icon: Icons.my_location,
                    tooltip: '현재 위치',
                    isLoading: _isLocating,
                    onTap: _isLocating ? null : _goToCurrentLocation,
                  ),
                ),
              ),
            ),
            Positioned(
              right: AppSpacing.md,
              bottom: gpsBottom + 52,
              child: IgnorePointer(
                ignoring: !isAiSheetCollapsed,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: isAiSheetCollapsed ? 1 : 0,
                  child: _RoundIconButton(
                    icon: Icons.auto_awesome,
                    tooltip: 'AI 장소 추천 열기',
                    onTap: _openAiRecommendations,
                  ),
                ),
              ),
            ),
            NotificationListener<DraggableScrollableNotification>(
              onNotification: (notification) {
                if (notification.extent != _aiSheetExtent) {
                  setState(() => _aiSheetExtent = notification.extent);
                }
                return false;
              },
              child: DraggableScrollableSheet(
                controller: _aiSheetController,
                minChildSize: 0,
                initialChildSize: 0.22,
                maxChildSize: 0.90,
                snap: true,
                snapSizes: const [0.50],
                builder: (context, scrollController) => AiRecommendationContent(
                  scrollController: scrollController,
                  showSheetHeader: true,
                  onRecommendationSelected: _showRecommendedPlaceOnMap,
                  api: widget.aiRecommendationsApi,
                  savedPlacesApi: widget.savedPlacesApi,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SearchButton extends StatelessWidget {
  const _SearchButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
      elevation: 2,
      shadowColor: AppColors.ink.withValues(alpha: 0.16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        child: const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: AppColors.deepNavy),
              SizedBox(width: AppSpacing.xs),
              Text(
                '장소 또는 주소 검색',
                style: TextStyle(color: AppColors.muted, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.paleMint,
      borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
      elevation: 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              const Icon(Icons.keyboard_arrow_down, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isLoading = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    const background = AppColors.surface;
    const foreground = AppColors.deepNavy;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        shape: const CircleBorder(),
        elevation: 2,
        shadowColor: AppColors.ink.withValues(alpha: 0.18),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 44,
            height: 44,
            child: isLoading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(icon, color: foreground, size: 21),
          ),
        ),
      ),
    );
  }
}
