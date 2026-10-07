import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/place.dart';
import '../../ai/screens/ai_recommendation_screen.dart';
import '../models/current_location.dart';
import '../models/map_filter.dart';
import '../models/map_place.dart';
import '../models/map_search_place.dart';
import '../widgets/map_filter_sheet.dart';
import '../widgets/map_view.dart';
import '../widgets/place_preview_sheet.dart';
import '../services/current_location_service.dart';
import 'place_detail_screen.dart';
import 'place_search_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    this.selectedGroupId,
    this.locationService,
    this.requestedFilters,
  });

  final String? selectedGroupId;
  final CurrentLocationService? locationService;
  final Set<MapFilter>? requestedFilters;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  Set<MapFilter> _selectedFilters = Set.of(MapFilter.values);
  MapPlace? _selectedPlace;
  MapSearchPlace? _selectedSearchPlace;
  CurrentLocation? _currentLocation;
  var _currentLocationRequestId = 0;
  var _isLocating = false;
  bool _isSatellite = false;

  Future<void> _goToCurrentLocation() async {
    if (_isLocating) return;
    setState(() => _isLocating = true);
    try {
      final location =
          await (widget.locationService ??
                  const GeolocatorCurrentLocationService())
              .getCurrentLocation();
      if (!mounted) return;
      setState(() {
        _currentLocation = location;
        _currentLocationRequestId++;
      });
    } on CurrentLocationFailure catch (failure) {
      if (!mounted) return;
      final message = switch (failure.reason) {
        CurrentLocationFailureReason.serviceDisabled => '위치 서비스를 켜주세요.',
        CurrentLocationFailureReason.permissionDenied =>
          '현재 위치를 사용하려면 위치 권한이 필요합니다.',
        CurrentLocationFailureReason.permissionPermanentlyDenied =>
          '위치 권한이 영구적으로 거부되었습니다. 설정에서 허용해주세요.',
        CurrentLocationFailureReason.timeout ||
        CurrentLocationFailureReason.unavailable =>
          '현재 위치를 확인하지 못했습니다. 다시 시도해주세요.',
      };
      _showMessage(message);
    } catch (_) {
      if (mounted) {
        _showMessage('현재 위치를 확인하지 못했습니다. 다시 시도해주세요.');
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.requestedFilters != null) {
      _selectedFilters = Set.of(widget.requestedFilters!);
    } else if (widget.selectedGroupId != null) {
      _selectedFilters = _filtersForGroupId(widget.selectedGroupId);
    }
  }

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestedFilters != widget.requestedFilters &&
        widget.requestedFilters != null) {
      setState(() {
        _selectedFilters = Set.of(widget.requestedFilters!);
        _selectedPlace = null;
      });
    } else if (oldWidget.selectedGroupId != widget.selectedGroupId) {
      setState(() {
        _selectedFilters = _filtersForGroupId(widget.selectedGroupId);
        _selectedPlace = null;
      });
    }
  }

  Set<MapFilter> _filtersForGroupId(String? groupId) {
    if (groupId == null) return Set.of(MapFilter.values);
    return {
      MapFilter.values.firstWhere(
        (filter) => filter.name == groupId,
        orElse: () => MapFilter.mine,
      ),
    };
  }

  static const List<MapPlace> _places = [];

  List<MapPlace> get _visiblePlaces => _places
      .where((place) => place.filters.any(_selectedFilters.contains))
      .toList();

  bool get _areAllFiltersSelected =>
      _selectedFilters.length == MapFilter.values.length &&
      _selectedFilters.containsAll(MapFilter.values);

  String get _filterLabel {
    if (_areAllFiltersSelected) return '전체';
    if (_selectedFilters.isEmpty) return '기록 필터';
    if (_selectedFilters.length == 1) return _selectedFilters.single.label;
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
      builder: (_) => MapFilterSheet(selectedFilters: _selectedFilters),
    );

    if (filters != null) {
      setState(() {
        _selectedFilters = filters;
        if (_selectedPlace != null &&
            !_visiblePlaces.contains(_selectedPlace)) {
          _selectedPlace = null;
        }
      });
    }
  }

  Future<void> _openPlacePreview(MapPlace place) async {
    setState(() => _selectedPlace = place);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => PlacePreviewSheet(
        place: place,
        onViewDetails: () {
          Navigator.pop(sheetContext);
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const PlaceDetailScreen()),
          );
        },
      ),
    );
    if (mounted) setState(() => _selectedPlace = null);
  }

  Future<void> _openPlaceSearch() async {
    final selectedPlace = await Navigator.of(context).push<Place>(
      MaterialPageRoute<Place>(builder: (_) => const PlaceSearchScreen()),
    );
    if (!mounted || selectedPlace == null) return;
    final searchPlace = MapSearchPlace.fromPlace(selectedPlace);
    if (!searchPlace.hasValidCoordinates) {
      _showMessage('선택한 장소의 좌표가 올바르지 않습니다.');
      return;
    }
    setState(() => _selectedSearchPlace = searchPlace);
  }

  Future<void> _openAiRecommendations() async {
    final selectedPlace = await Navigator.of(context).push<Place>(
      MaterialPageRoute<Place>(builder: (_) => const AiRecommendationScreen()),
    );
    if (!mounted || selectedPlace == null) return;
    _showMessage("'${selectedPlace.name}'을 추천 장소로 선택했어요.");
  }

  @override
  Widget build(BuildContext context) {
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
              const SizedBox(width: AppSpacing.xs),
              _RoundIconButton(
                icon: Icons.tune_rounded,
                tooltip: '기록 필터',
                onTap: _openFilterSheet,
              ),
            ],
          ),
        ),
        Positioned(
          top: 68,
          left: AppSpacing.md,
          child: _FilterChip(label: _filterLabel, onTap: _openFilterSheet),
        ),
        Positioned(
          right: AppSpacing.md,
          bottom: AppSpacing.lg,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RoundIconButton(
                icon: _isSatellite ? Icons.satellite_alt : Icons.map_outlined,
                tooltip: '지도 유형 전환',
                onTap: () => setState(() => _isSatellite = !_isSatellite),
              ),
              const SizedBox(height: AppSpacing.xs),
              _RoundIconButton(
                icon: Icons.my_location,
                tooltip: '현재 위치',
                onTap: _goToCurrentLocation,
              ),
              const SizedBox(height: AppSpacing.xs),
              _RoundIconButton(
                icon: Icons.auto_awesome,
                tooltip: 'AI 추천',
                isPrimary: true,
                onTap: _openAiRecommendations,
              ),
            ],
          ),
        ),
      ],
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
              const Icon(Icons.groups_outlined, size: 17),
              const SizedBox(width: AppSpacing.xxs),
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
    this.isPrimary = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final background = isPrimary ? AppColors.deepNavy : AppColors.surface;
    final foreground = isPrimary ? Colors.white : AppColors.deepNavy;
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
            child: Icon(icon, color: foreground, size: 21),
          ),
        ),
      ),
    );
  }
}
