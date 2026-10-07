import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/emotion.dart';
import '../../../shared/models/group.dart';
import '../../map/widgets/kakao_map_webview.dart';
import '../widgets/emotion_picker.dart';
import '../widgets/group_picker.dart';
import '../widgets/photo_placeholder_picker.dart';

class RecordComposeScreen extends StatefulWidget {
  const RecordComposeScreen({super.key, required this.onExitToMap});

  final VoidCallback onExitToMap;

  @override
  State<RecordComposeScreen> createState() => _RecordComposeScreenState();
}

class _RecordComposeScreenState extends State<RecordComposeScreen> {
  final _storyController = TextEditingController();
  final _placeNameController = TextEditingController();
  final List<String> _photoPlaceholders = [];
  final Set<String> _selectedGroupIds = {};
  Emotion? _selectedEmotion;
  double? _selectedLatitude;
  double? _selectedLongitude;
  String? _selectedRoadAddress;
  var _isResolvingPlace = false;
  var _isSearchingPlace = false;
  var _hasSelectedPlace = false;
  String? _placeSearchMessage;
  List<KakaoPlaceSearchResult> _placeSearchResults = const [];
  KakaoPlaceSearchRequest? _placeSearchRequest;
  KakaoMapSelectionRequest? _mapSelectionRequest;
  var _placeSearchRequestId = 0;
  var _mapSelectionRequestId = 0;
  bool _isPrivate = false;
  int _photoSequence = 0;

  static const _groups = [
    Group(id: 'group-yeonnam', name: '연남 산책단', memberCount: 3),
    Group(id: 'group-neighborhood', name: '동네 친구들', memberCount: 5),
    Group(id: 'group-travel', name: '여행팟', memberCount: 4),
    Group(id: 'group-bookclub', name: '독서모임', memberCount: 4),
    Group(id: 'group-running', name: '러닝크루', memberCount: 6),
  ];

  @override
  void dispose() {
    _storyController.dispose();
    _placeNameController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _addPhoto(String source) {
    setState(() {
      _photoSequence += 1;
      _photoPlaceholders.add('$source-$_photoSequence');
    });
  }

  void _onLocationChanged(double latitude, double longitude) {
    setState(() {
      _selectedLatitude = latitude;
      _selectedLongitude = longitude;
      _isResolvingPlace = true;
      _hasSelectedPlace = false;
    });
  }

  void _onPlaceResolved(KakaoPlaceSelection selection) {
    debugPrint('[PLACE_DEBUG] onPlaceResolved: ${selection.placeName}');
    setState(() {
      _selectedLatitude = selection.latitude;
      _selectedLongitude = selection.longitude;
      _selectedRoadAddress = selection.roadAddress;
      _isResolvingPlace = false;
      _hasSelectedPlace = selection.placeName.isNotEmpty;
      _placeNameController.value = TextEditingValue(
        text: selection.placeName,
        selection: TextSelection.collapsed(offset: selection.placeName.length),
      );
    });
    debugPrint(
      '[PLACE_DEBUG] controller text after update: '
      '${_placeNameController.text}',
    );
  }

  void _submitPlaceSearch([String? rawKeyword]) {
    final keyword = (rawKeyword ?? _placeNameController.text).trim();
    debugPrint('[SEARCH_DEBUG] submit keyword: $keyword');
    if (keyword.length < 2) {
      setState(() {
        _isSearchingPlace = false;
        _placeSearchResults = const [];
        _placeSearchMessage = '두 글자 이상 입력해 주세요.';
        _hasSelectedPlace = false;
      });
      return;
    }

    setState(() {
      _isSearchingPlace = true;
      _placeSearchResults = const [];
      _placeSearchMessage = null;
      _hasSelectedPlace = false;
      _placeSearchRequest = KakaoPlaceSearchRequest(
        id: ++_placeSearchRequestId,
        keyword: keyword,
        latitude: _selectedLatitude ?? 35.110791,
        longitude: _selectedLongitude ?? 126.877343,
      );
    });
  }

  void _onPlaceSearchResults(KakaoPlaceSearchResults results) {
    if (!mounted || results.keyword != _placeSearchRequest?.keyword) return;
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
    final address = place.roadAddress.isNotEmpty ? place.roadAddress : place.address;
    setState(() {
      _selectedLatitude = place.latitude;
      _selectedLongitude = place.longitude;
      _selectedRoadAddress = address;
      _hasSelectedPlace = true;
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
      );
    });
  }

  void _onPlaceSearchTextChanged(String _) {
    if (_hasSelectedPlace || _placeSearchMessage != null) {
      setState(() {
        _hasSelectedPlace = false;
        _placeSearchMessage = null;
      });
    }
  }

  String _formatDistance(double? distance) {
    if (distance == null) return '';
    if (distance < 1000) return '거리 ${distance.round()}m';
    return '거리 ${(distance / 1000).toStringAsFixed(1)}km';
  }

  void _showCurrentLocationUnavailable() {
    _showMessage('현재 위치 기능은 추후 연결됩니다.');
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

  void _publish() {
    if (_photoPlaceholders.isEmpty) {
      _showMessage('사진을 한 장 이상 추가해 주세요.');
      return;
    }
    if (_selectedEmotion == null) {
      _showMessage('이곳의 느낌을 하나 선택해 주세요.');
      return;
    }
    if (_selectedLatitude == null ||
        _selectedLongitude == null ||
        !_hasSelectedPlace ||
        _placeNameController.text.trim().isEmpty) {
      _showMessage('기록할 장소를 선택해 주세요.');
      return;
    }
    if (!_isPrivate && _selectedGroupIds.isEmpty) {
      _showMessage('공유할 모임을 하나 이상 선택해 주세요.');
      return;
    }

    setState(() {
      _photoPlaceholders.clear();
      _selectedGroupIds.clear();
      _selectedEmotion = null;
      _selectedLatitude = null;
      _selectedLongitude = null;
      _selectedRoadAddress = null;
      _hasSelectedPlace = false;
      _placeNameController.clear();
      _isPrivate = false;
      _storyController.clear();
    });
    _showMessage('기록이 작성되었습니다.');
    widget.onExitToMap();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.paper,
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
            photos: _photoPlaceholders,
            onAddCamera: () => _addPhoto('camera'),
            onAddGallery: () => _addPhoto('gallery'),
            onRemove: (id) => setState(() => _photoPlaceholders.remove(id)),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _SectionTitle(title: '이곳의 느낌', isRequired: true),
          const SizedBox(height: AppSpacing.xs),
          EmotionPicker(
            selectedEmotion: _selectedEmotion,
            onSelected: (emotion) => setState(() => _selectedEmotion = emotion),
          ),
          const SizedBox(height: AppSpacing.lg),
          const _SectionTitle(title: '어디에서 보냈나요?', isRequired: true),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            child: SizedBox(
              height: 230,
              child: KakaoMapWebView(
                selectionMode: true,
                initialLatitude: 35.110791,
                initialLongitude: 126.877343,
                onLocationChanged: _onLocationChanged,
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
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ),
              TextButton.icon(
                onPressed: _showCurrentLocationUnavailable,
                icon: const Icon(Icons.my_location_outlined, size: 18),
                label: const Text('현재 위치 다시 찾기'),
              ),
            ],
          ),
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
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
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
                      [address, secondary, distance]
                          .where((value) => value.isNotEmpty)
                          .join('\n'),
                    ),
                    onTap: () => _selectPlaceSearchResult(place),
                  );
                },
              ),
            ),
          if (_selectedRoadAddress case final String address when address.isNotEmpty)
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
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
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
              onPressed: _publish,
              child: const Text('기록 남기기'),
            ),
          ),
        ],
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
