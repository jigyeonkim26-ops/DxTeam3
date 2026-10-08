import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/emotion.dart';
import '../../../shared/models/group.dart';
import '../../../shared/models/place.dart';
import '../widgets/emotion_picker.dart';
import '../widgets/group_picker.dart';
import '../widgets/photo_placeholder_picker.dart';
import '../../map/screens/place_search_screen.dart';
import '../../map/widgets/kakao_map_webview.dart';
import '../../map/models/current_location.dart';
import '../../map/services/current_location_service.dart';
import '../services/record_api.dart';
import '../../../core/network/api_client.dart';

import 'package:image_picker/image_picker.dart';

class RecordComposeScreen extends StatefulWidget {
  const RecordComposeScreen({
    super.key,
    required this.onExitToMap,
    this.recordApi,
    this.onPublished,
    this.pickPhotos,
    this.pickPlace,
    this.locationService,
  });

  final CurrentLocationService? locationService;
  final VoidCallback onExitToMap;
  final VoidCallback? onPublished;
  final RecordApi? recordApi;
  final Future<List<XFile>> Function(ImageSource)? pickPhotos;
  final Future<Place?> Function(BuildContext)? pickPlace;

  @override
  State<RecordComposeScreen> createState() => _RecordComposeScreenState();
}

class _RecordComposeScreenState extends State<RecordComposeScreen> {
  final _storyController = TextEditingController();
  final _placeNameController = TextEditingController();
  CurrentLocation? _currentLocation;
  int _currentLocationRequestId = 0;
  bool _isLocating = false;
  final List<XFile> _photos = [];
  final Set<String> _selectedGroupIds = {};
  Emotion? _selectedEmotion;
  Place? _selectedPlace;
  double? _selectedLatitude;
  double? _selectedLongitude;
  String? _selectedRoadAddress;
  var _isResolvingPlace = false;
  // The compose flow now selects its location directly on the map. Keep the
  // legacy search plumbing isolated until the map bridge is removed entirely.
  final bool _showPlaceSearchUi = false;
  var _isSearchingPlace = false;
  String? _placeSearchMessage;
  List<KakaoPlaceSearchResult> _placeSearchResults = const [];
  KakaoPlaceSearchRequest? _placeSearchRequest;
  KakaoMapSelectionRequest? _mapSelectionRequest;
  var _placeSearchRequestId = 0;
  var _mapSelectionRequestId = 0;

  bool _isPrivate = false;
  late final RecordApi _api;
  List<Group> _groups = [];
  bool _isPublishing = false;
  bool _isLoadingGroups = true;
  String? _groupError;

  @override
  void initState() {
    super.initState();
    _api = widget.recordApi ?? RecordApi();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    setState(() {
      _isLoadingGroups = true;
      _groupError = null;
    });
    try {
      final groups = await _api.groups();
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _selectedGroupIds.retainAll(groups.map((g) => g.id));
        _groupError = null;
        _isLoadingGroups = false;
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _groupError = error.message;
          _isLoadingGroups = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _groupError = '모임을 불러오지 못했습니다.';
          _isLoadingGroups = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _storyController.dispose();
    _placeNameController.dispose();
    if (widget.recordApi == null) _api.close();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addPhoto(ImageSource source) async {
    if (_isPublishing) return;
    try {
      final images = widget.pickPhotos != null
          ? await widget.pickPhotos!(source)
          : source == ImageSource.gallery
          ? await ImagePicker().pickMultiImage(imageQuality: 85)
          : [
              if (await ImagePicker().pickImage(
                    source: source,
                    imageQuality: 85,
                  )
                  case final XFile image)
                image,
            ];
      if (!mounted) return;
      if (_photos.length + images.length > 5) {
        _showMessage('사진은 최대 5장 선택해 주세요.');
        return;
      }
      for (final image in images) {
        if (await image.length() > 10 * 1024 * 1024) {
          if (mounted) _showMessage('사진 한 장은 10MB 이하로 선택해 주세요.');
          return;
        }
      }
      if (mounted) setState(() => _photos.addAll(images));
    } catch (_) {
      if (mounted) _showMessage('사진을 선택하지 못했습니다. 사진 접근 권한을 확인해 주세요.');
    }
  }

  Future<void> _selectPlace() async {
    final place = widget.pickPlace != null
        ? await widget.pickPlace!(context)
        : await Navigator.of(context).push<Place>(
            MaterialPageRoute(builder: (_) => const PlaceSearchScreen()),
          );
    if (!mounted || place == null) return;
    if (!RegExp(r'^\d+$').hasMatch(place.id)) {
      _showMessage('검색 결과에서 장소를 다시 선택해 주세요.');
      return;
    }
    setState(() {
      _selectedPlace = place;
      _selectedLatitude = place.latitude;
      _selectedLongitude = place.longitude;
      _selectedRoadAddress = place.address;
      _placeNameController.text = place.name;
      _isResolvingPlace = false;
      _isSearchingPlace = false;
      _placeSearchResults = const [];
      _placeSearchRequest = null;
      _placeSearchMessage = null;
      _mapSelectionRequest = KakaoMapSelectionRequest(
        id: ++_mapSelectionRequestId,
        latitude: place.latitude,
        longitude: place.longitude,
        placeName: place.name,
        placeId: place.id,
        address: place.address,
      );
    });
  }

  void _submitPlaceSearch([String? rawKeyword]) {
    final keyword = (rawKeyword ?? _placeNameController.text).trim();
    debugPrint('[SEARCH_DEBUG] submit keyword: $keyword');
    if (keyword.length < 2) {
      setState(() {
        _isSearchingPlace = false;
        _placeSearchResults = const [];
        _placeSearchMessage = '두 글자 이상 입력해 주세요.';
        _selectedPlace = null;
      });
      return;
    }

    setState(() {
      _isSearchingPlace = true;
      _placeSearchResults = const [];
      _placeSearchMessage = null;
      _selectedPlace = null;
      _placeSearchRequest = KakaoPlaceSearchRequest(
        id: ++_placeSearchRequestId,
        keyword: keyword,
        latitude: _selectedLatitude ?? _currentLocation?.latitude ?? 37.5663,
        longitude:
            _selectedLongitude ?? _currentLocation?.longitude ?? 126.9779,
      );
    });
  }

  void _onPlaceSearchResults(KakaoPlaceSearchResults results) {
    if (!mounted ||
        !_isSearchingPlace ||
        results.keyword != _placeSearchRequest?.keyword ||
        results.requestId != _placeSearchRequest?.id) {
      return;
    }
    debugPrint('[SEARCH_DEBUG] UI result count: ${results.places.length}');
    setState(() {
      _isSearchingPlace = false;
      _placeSearchResults = results.places;
      _placeSearchMessage = results.isError
          ? '장소 검색에 실패했습니다. 잠시 후 다시 시도해 주세요.'
          : results.places.isEmpty
          ? '검색 결과가 없어요.\n다른 장소명이나 주소로 검색해보세요.'
          : null;
    });
  }

  void _selectPlaceSearchResult(KakaoPlaceSearchResult place) {
    if (!RegExp(r'^\d+$').hasMatch(place.id) ||
        !place.latitude.isFinite ||
        !place.longitude.isFinite ||
        place.latitude.abs() > 90 ||
        place.longitude.abs() > 180) {
      _showMessage('검색 결과에서 유효한 장소를 다시 선택해 주세요.');
      return;
    }
    final address = place.roadAddress.isNotEmpty
        ? place.roadAddress
        : place.address;
    setState(() {
      _selectedLatitude = place.latitude;
      _selectedLongitude = place.longitude;
      _selectedRoadAddress = address;
      _selectedPlace = Place(
        id: place.id,
        name: place.placeName,
        address: address,
        latitude: place.latitude,
        longitude: place.longitude,
      );
      _isResolvingPlace = false;
      _isSearchingPlace = false;
      _placeSearchResults = const [];
      _placeSearchMessage = null;
      _placeNameController.value = TextEditingValue(
        text: place.placeName,
        selection: TextSelection.collapsed(offset: place.placeName.length),
      );
      _mapSelectionRequest = KakaoMapSelectionRequest(
        id: ++_mapSelectionRequestId,
        latitude: place.latitude,
        longitude: place.longitude,
        placeName: place.placeName,
        placeId: place.id,
        address: address,
      );
    });
  }

  void _onPlaceSearchTextChanged(String _) {
    setState(() {
      _selectedPlace = null;
      _selectedRoadAddress = null;
      _placeSearchRequest = null;
      _mapSelectionRequest = null;
      _placeSearchRequestId++;
      _isSearchingPlace = false;
      _placeSearchResults = const [];
      _placeSearchMessage = null;
    });
  }

  String _formatDistance(double? distance) {
    if (distance == null) return '';
    if (distance < 1000) return '거리 ${distance.round()}m';
    return '거리 ${(distance / 1000).toStringAsFixed(1)}km';
  }

  void _onPlaceResolved(KakaoPlaceSelection selection) {
    if (!mounted ||
        !_isResolvingPlace ||
        selection.latitude != _selectedLatitude ||
        selection.longitude != _selectedLongitude) {
      return;
    }
    setState(() {
      _isResolvingPlace = false;
      final place = selection.place;
      final validPlace =
          place != null &&
          RegExp(r'^\d+$').hasMatch(place.id) &&
          place.placeName.trim().isNotEmpty &&
          place.latitude.isFinite &&
          place.longitude.isFinite &&
          place.latitude.abs() <= 90 &&
          place.longitude.abs() <= 180;
      _selectedRoadAddress = validPlace && place.roadAddress.isNotEmpty
          ? place.roadAddress
          : validPlace && place.address.isNotEmpty
          ? place.address
          : selection.roadAddress.isNotEmpty
          ? selection.roadAddress
          : selection.lotAddress;
      _selectedPlace = validPlace
          ? Place(
              id: place.id,
              name: place.placeName,
              address: _selectedRoadAddress,
              latitude: place.latitude,
              longitude: place.longitude,
            )
          : null;
      _placeNameController.text = _selectedPlace?.name ?? '';
    });
  }

  void _onLocationChanged(double latitude, double longitude) {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() > 90 ||
        longitude.abs() > 180) {
      return;
    }
    setState(() {
      _selectedLatitude = latitude;
      _selectedLongitude = longitude;
      _isResolvingPlace = true;
      if (_selectedPlace?.latitude != latitude ||
          _selectedPlace?.longitude != longitude) {
        _selectedPlace = null;
        _selectedRoadAddress = null;
        _placeNameController.clear();
        _mapSelectionRequest = null;
      }
    });
  }

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
      if (mounted) _showMessage('현재 위치를 확인하지 못했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _togglePrivate(bool value) {
    setState(() {
      _isPrivate = value;
      if (value) _selectedGroupIds.clear();
    });
  }

  void _toggleGroup(Group group) {
    setState(() {
      if (!_selectedGroupIds.add(group.id)) _selectedGroupIds.remove(group.id);
    });
  }

  bool get _areAllGroupsSelected =>
      _groups.isNotEmpty && _selectedGroupIds.length == _groups.length;

  void _toggleAllGroups(bool shouldSelectAll) {
    setState(() {
      if (shouldSelectAll) {
        _selectedGroupIds.addAll(_groups.map((group) => group.id));
      } else {
        _selectedGroupIds.clear();
      }
    });
  }

  Future<void> _publish() async {
    if (_isPublishing) return;
    if (_photos.isEmpty) {
      _showMessage('사진을 한 장 이상 추가해 주세요.');
      return;
    }
    if (_selectedEmotion == null) {
      _showMessage('이곳의 느낌을 하나 선택해 주세요.');
      return;
    }
    if (_selectedPlace == null ||
        !RegExp(r'^\d+$').hasMatch(_selectedPlace!.id)) {
      _showMessage('기록할 장소를 선택해 주세요.');
      return;
    }
    if (!_isPrivate && _selectedGroupIds.isEmpty) {
      _showMessage('공유할 모임을 하나 이상 선택해 주세요.');
      return;
    }

    setState(() => _isPublishing = true);
    try {
      await _api.create(
        photos: List.of(_photos),
        emotion: _selectedEmotion!,
        place: _selectedPlace!,
        content: _storyController.text,
        isPrivate: _isPrivate,
        groupIds: Set.of(_selectedGroupIds),
      );
      if (!mounted) return;
      setState(() {
        _photos.clear();
        _selectedGroupIds.clear();
        _selectedEmotion = null;
        _selectedPlace = null;
        _placeNameController.clear();
        _currentLocation = null;
        _selectedLatitude = null;
        _selectedLongitude = null;
        _selectedRoadAddress = null;
        _isResolvingPlace = false;
        _isSearchingPlace = false;
        _placeSearchResults = const [];
        _placeSearchRequest = null;
        _mapSelectionRequest = null;
        _placeSearchMessage = null;
        _isPrivate = false;
        _storyController.clear();
      });
      _showMessage('기록이 작성되었습니다.');
      (widget.onPublished ?? widget.onExitToMap)();
    } on ApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.paper,
      child: AbsorbPointer(
        absorbing: _isPublishing,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg + MediaQuery.viewInsetsOf(context).bottom,
          ),
          children: [
            const Text(
              '새 기록',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            const Text(
              '지금 이 순간의 장소와 감정을 남겨 보세요.',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.lg),
            const _SectionTitle(title: '사진', isRequired: true),
            const SizedBox(height: AppSpacing.xs),
            PhotoPlaceholderPicker(
              photos: _photos,
              onAddCamera: () => _addPhoto(ImageSource.camera),
              onAddGallery: () => _addPhoto(ImageSource.gallery),
              onRemove: (photo) => setState(() => _photos.remove(photo)),
            ),
            const SizedBox(height: AppSpacing.lg),
            const _SectionTitle(title: '이곳의 느낌', isRequired: true),
            const SizedBox(height: AppSpacing.xs),
            EmotionPicker(
              selectedEmotion: _selectedEmotion,
              onSelected: (emotion) =>
                  setState(() => _selectedEmotion = emotion),
            ),
            const SizedBox(height: AppSpacing.lg),
            const _SectionTitle(title: '어디에서 보냈나요?', isRequired: true),
            const SizedBox(height: AppSpacing.xs),
            _PlaceSelector(
              place: _selectedPlace,
              address: _selectedRoadAddress,
              onTap: _selectPlace,
            ),
            const SizedBox(height: AppSpacing.sm),
            if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
              ClipRRect(
                borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                child: SizedBox(
                  height: 230,
                  child: KakaoMapWebView(
                    selectionMode: true,
                    initialLatitude: _currentLocation?.latitude ?? 37.5663,
                    initialLongitude: _currentLocation?.longitude ?? 126.9779,
                    onLocationChanged: _onLocationChanged,
                    currentLocation: _currentLocation,
                    currentLocationRequestId: _currentLocationRequestId,
                    onPlaceResolved: _onPlaceResolved,
                    placeSearchRequest: _placeSearchRequest,
                    onPlaceSearchResults: _onPlaceSearchResults,
                    selectionRequest: _mapSelectionRequest,
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            if (_isResolvingPlace) ...[
              const Text(
                '장소 정보 확인 중...',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const Text(
                '주변 장소 또는 주소를 찾고 있어요.',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            if (!_isResolvingPlace &&
                _selectedLatitude != null &&
                _selectedPlace == null)
              const Text(
                '주변 장소를 찾지 못했어요. 장소 검색으로 선택해 주세요.',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            const Text(
              '핀을 드래그하거나 지도를 탭해 정확한 위치를 정해요.',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedLatitude == null || _selectedLongitude == null
                        ? '선택 위치를 불러오는 중이에요.'
                        : '선택 위치  '
                              '${_selectedLatitude!.toStringAsFixed(6)}, '
                              '${_selectedLongitude!.toStringAsFixed(6)}',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _isLocating ? null : _goToCurrentLocation,
                  icon: const Icon(Icons.my_location_outlined, size: 18),
                  label: Text(_isLocating ? '위치 확인 중...' : '현재 위치 다시 찾기'),
                ),
              ],
            ),
            if (_showPlaceSearchUi) ...[
              const SizedBox(height: AppSpacing.sm),
              const Text(
                '장소 검색',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: _placeNameController,
                maxLength: 50,
                textInputAction: TextInputAction.search,
                onChanged: _onPlaceSearchTextChanged,
                onSubmitted: _submitPlaceSearch,
                decoration: InputDecoration(
                  hintText: '장소 또는 주소를 검색해 주세요',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    tooltip: '장소 검색',
                    onPressed: _submitPlaceSearch,
                  ),
                ),
              ),
              if (_isSearchingPlace)
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    '장소를 검색하고 있어요...',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ),
              if (_placeSearchMessage case final String message)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
              if (_placeSearchResults.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _placeSearchResults.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final place = _placeSearchResults[index];
                      final address = place.roadAddress.isNotEmpty
                          ? place.roadAddress
                          : place.address;
                      final distance = _formatDistance(place.distance);
                      final secondary = place.categoryName.isNotEmpty
                          ? place.categoryName
                          : place.phone;
                      return ListTile(
                        dense: true,
                        title: Text(place.placeName),
                        subtitle: Text(
                          [
                            address,
                            secondary,
                            distance,
                          ].where((value) => value.isNotEmpty).join('\n'),
                        ),
                        onTap: () => _selectPlaceSearchResult(place),
                      );
                    },
                  ),
                ),
            ],
            if (_selectedRoadAddress case final String address
                when address.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  address,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            const _SectionTitle(title: '이 순간을 한 줄로'),
            const SizedBox(height: AppSpacing.xs),
            TextField(
              controller: _storyController,
              minLines: 4,
              maxLines: 6,
              maxLength: 300,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: '짧은 기억을 남겨보세요. 오늘의 순간이 오래 기억될 거예요.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Card(
              child: SwitchListTile.adaptive(
                value: _isPrivate,
                onChanged: _togglePrivate,
                activeThumbColor: AppColors.coral,
                title: const Text(
                  '나만 보기',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('모임에 공유하지 않고 나만 볼 수 있어요.'),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                const Expanded(child: _SectionTitle(title: '공유할 모임')),
                if (!_isPrivate)
                  Text(
                    _selectedGroupIds.isEmpty
                        ? '최소 1개 선택'
                        : '${_selectedGroupIds.length}개 선택됨',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            if (_isPrivate)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  '나만 보기 기록은 모임에 공유되지 않아요.',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            if (_isLoadingGroups) const LinearProgressIndicator(),
            if (_groupError != null)
              TextButton(
                onPressed: _loadGroups,
                child: Text('$_groupError 다시 시도'),
              ),
            if (!_isLoadingGroups &&
                _groupError == null &&
                _groups.isEmpty &&
                !_isPrivate)
              const Text('가입한 모임이 없습니다. 나만 보기로 기록할 수 있어요.'),
            GroupPicker(
              groups: _groups,
              selectedGroupIds: _selectedGroupIds,
              isDisabled: _isPrivate,
              areAllSelected: _areAllGroupsSelected,
              onChanged: _toggleGroup,
              onSelectAll: _toggleAllGroups,
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isPublishing ? null : _publish,
                child: Text(_isPublishing ? '저장 중...' : '기록 남기기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.isRequired = false});

  final String title;
  final bool isRequired;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          color: AppColors.ink,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        children: [
          TextSpan(text: title),
          if (isRequired)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: AppColors.coral),
            ),
        ],
      ),
    );
  }
}

class _PlaceSelector extends StatelessWidget {
  const _PlaceSelector({
    required this.place,
    this.address,
    required this.onTap,
  });

  final Place? place;
  final String? address;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: const CircleAvatar(
          backgroundColor: AppColors.paleMint,
          foregroundColor: AppColors.deepNavy,
          child: Icon(Icons.location_on_outlined),
        ),
        title: Text(
          place?.name ?? '장소를 선택해 주세요',
          style: TextStyle(
            color: place == null ? AppColors.muted : AppColors.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: (place?.address ?? address)?.isNotEmpty == true
            ? Text(place?.address ?? address!)
            : null,
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
