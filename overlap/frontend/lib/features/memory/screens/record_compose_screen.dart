import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/emotion.dart';
import '../../../shared/models/group.dart';
import '../../../shared/models/place.dart';
import '../../map/screens/place_search_screen.dart';
import '../models/memory_create_request.dart';
import '../models/place_public.dart';
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
  final List<String> _photoPlaceholders = [];
  final Set<String> _selectedGroupIds = {};
  Emotion? _selectedEmotion;
  _SelectedKakaoPlace? _selectedPlace;
  bool _isPrivate = false;
  bool _isPublishing = false;
  int _photoSequence = 0;

  List<Group> _groups = const [];
  bool _isLoadingGroups = true;
  bool _groupLoadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    try {
      final groups = await ApiClient.getGroups();
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _groupLoadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _groups = const [];
        _groupLoadFailed = true;
      });
      _showMessage('\uBAA8\uC784 \uBAA9\uB85D\uC744 \uBD88\uB7EC\uC624\uC9C0 \uBABB\uD588\uC5B4\uC694.');
    } finally {
      if (mounted) setState(() => _isLoadingGroups = false);
    }
  }

  @override
  void dispose() {
    _storyController.dispose();
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

  Future<void> _selectPlace() async {
    final place = await Navigator.of(context).push<Place>(
      MaterialPageRoute<Place>(builder: (_) => const PlaceSearchScreen()),
    );
    if (place != null) {
      setState(() => _selectedPlace = _SelectedKakaoPlace.fromPlace(place));
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

  String _normalizePlaceText(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  PlacePublic? _findMatchingPlace(
    List<PlacePublic> serverPlaces,
    _SelectedKakaoPlace selectedPlace,
  ) {
    final selectedName = _normalizePlaceText(selectedPlace.name);
    final selectedAddress = _normalizePlaceText(selectedPlace.address);
    for (final serverPlace in serverPlaces) {
      if (_normalizePlaceText(serverPlace.name) == selectedName &&
          _normalizePlaceText(serverPlace.address) == selectedAddress) {
        return serverPlace;
      }
    }
    return null;
  }

  Future<PlacePublic> _ensureServerPlace(
    int groupId,
    _SelectedKakaoPlace selectedPlace,
  ) async {
    final existing = _findMatchingPlace(
      await ApiClient.getGroupPlaces(groupId: groupId),
      selectedPlace,
    );
    if (existing != null) return existing;

    try {
      return await ApiClient.createGroupPlace(
        groupId: groupId,
        name: selectedPlace.name,
        address: selectedPlace.address,
        latitude: selectedPlace.latitude,
        longitude: selectedPlace.longitude,
      );
    } on ApiException catch (error) {
      if (error.statusCode != 409) rethrow;
      final afterConflict = await ApiClient.getGroupPlaces(groupId: groupId);
      final existingAfterConflict =
          _findMatchingPlace(afterConflict, selectedPlace);
      if (existingAfterConflict != null) return existingAfterConflict;
      rethrow;
    }
  }

  DateTime _visitedOnForSubmission() => DateTime.now();

  Future<void> _publish() async {
    if (_isPublishing) return;

    if (_photoPlaceholders.isEmpty) {
      _showMessage('\uC0AC\uC9C4\uC744 \uD55C \uC7A5 \uC774\uC0C1 \uCD94\uAC00\uD574 \uC8FC\uC138\uC694.');
      return;
    }
    if (_selectedEmotion == null) {
      _showMessage('\uAC10\uC815\uC744 \uC120\uD0DD\uD574 \uC8FC\uC138\uC694.');
      return;
    }
    if (_selectedPlace == null) {
      _showMessage('\uAE30\uB85D\uD560 \uC7A5\uC18C\uB97C \uC120\uD0DD\uD574 \uC8FC\uC138\uC694.');
      return;
    }
    if (!_isPrivate && _selectedGroupIds.isEmpty) {
      _showMessage('\uACF5\uC720\uD560 \uBAA8\uC784\uC744 \uD558\uB098 \uC774\uC0C1 \uC120\uD0DD\uD574 \uC8FC\uC138\uC694.');
      return;
    }
    if (_storyController.text.trim().isEmpty) {
      _showMessage('\uCF54\uBA58\uD2B8\uB97C \uC785\uB825\uD574 \uC8FC\uC138\uC694.');
      return;
    }
    if (_isPrivate) {
      _showMessage('\uD604\uC7AC API\uB294 \uBAA8\uC784\uC5D0 \uACF5\uC720\uD558\uB294 \uAE30\uB85D\uB9CC \uC9C0\uC6D0\uD569\uB2C8\uB2E4.');
      return;
    }

    // FastAPI accepts one group ID. Use the first selected group in selection order.
    final groupId = int.tryParse(_selectedGroupIds.first);
    if (groupId == null || groupId <= 0) {
      _showMessage('\uC120\uD0DD\uD55C \uBAA8\uC784\uC774 \uC11C\uBC84 ID\uC640 \uC5F0\uACB0\uB418\uC9C0 \uC54A\uC558\uC2B5\uB2C8\uB2E4.');
      return;
    }

    final selectedPlace = _selectedPlace!;
    setState(() => _isPublishing = true);
    try {
      final serverPlace = await _ensureServerPlace(groupId, selectedPlace);
      final request = MemoryCreateRequest(
        placeId: serverPlace.id,
        content: _storyController.text.trim(),
        visitedOn: _visitedOnForSubmission(),
        emotionCode: _selectedEmotion!.apiCode,
      );
      await ApiClient.createMemory(groupId: groupId, request: request);

      if (!mounted) return;
      setState(() {
        _photoPlaceholders.clear();
        _selectedGroupIds.clear();
        _selectedEmotion = null;
        _selectedPlace = null;
        _isPrivate = false;
        _storyController.clear();
      });
      _showMessage('\uAE30\uB85D\uC774 \uC800\uC7A5\uB418\uC5C8\uC5B4\uC694.');
      widget.onExitToMap();
    } catch (error) {
      if (mounted) _showMessage(error.toString());
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
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
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: widget.onExitToMap,
              icon: const Icon(Icons.arrow_back),
              tooltip: '지도 메인으로 돌아가기',
            ),
          ),
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
          _PlaceSelector(place: _selectedPlace?.asPlace(), onTap: _selectPlace),
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
          if (_isLoadingGroups)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.md),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_groups.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                _groupLoadFailed
                    ? '\uBAA8\uC784 \uBAA9\uB85D\uC744 \uB2E4\uC2DC \uBD88\uB7EC\uC640 \uC8FC\uC138\uC694.'
                    : '\uAC00\uC785\uB41C \uBAA8\uC784\uC774 \uC5C6\uC5B4\uC694.',
                style: const TextStyle(color: AppColors.muted),
                textAlign: TextAlign.center,
              ),
            )
          else
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
              child: _isPublishing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('기록 남기기'),
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

class _PlaceSelector extends StatelessWidget {
  const _PlaceSelector({required this.place, required this.onTap});

  final Place? place;
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
        subtitle: place == null ? null : Text(place!.address ?? ''),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}


/// PlaceSearchScreen returns Place.id as Kakao's external place ID.
/// Keep it separate from the integer ID returned by FastAPI PlacePublic.
class _SelectedKakaoPlace {
  const _SelectedKakaoPlace({
    required this.kakaoPlaceId,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  final String kakaoPlaceId;
  final String name;
  final String address;
  final double latitude;
  final double longitude;

  factory _SelectedKakaoPlace.fromPlace(Place place) => _SelectedKakaoPlace(
        kakaoPlaceId: place.id,
        name: place.name,
        address: place.address ?? '',
        latitude: place.latitude,
        longitude: place.longitude,
      );

  Place asPlace() => Place(
        id: kakaoPlaceId,
        name: name,
        address: address,
        latitude: latitude,
        longitude: longitude,
      );
}
