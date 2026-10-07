import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/emotion.dart';
import '../../../shared/models/group.dart';
import '../../../shared/models/place.dart';
import '../widgets/emotion_picker.dart';
import '../widgets/group_picker.dart';
import '../widgets/photo_placeholder_picker.dart';
import '../../map/screens/place_search_screen.dart';
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
  });

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
  final List<XFile> _photos = [];
  final Set<String> _selectedGroupIds = {};
  Emotion? _selectedEmotion;
  Place? _selectedPlace;
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
    }
  }

  @override
  void dispose() {
    _storyController.dispose();
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
    if (mounted && place != null) setState(() => _selectedPlace = place);
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
    if (_selectedPlace == null) {
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
    return ColoredBox(
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
            _PlaceSelector(place: _selectedPlace, onTap: _selectPlace),
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
