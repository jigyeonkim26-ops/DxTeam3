import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/emotion.dart';
import '../../../shared/models/group.dart';
import '../../../shared/models/place.dart';
import '../widgets/emotion_picker.dart';
import '../widgets/group_picker.dart';
import '../widgets/photo_placeholder_picker.dart';
import '../widgets/place_picker_sheet.dart';

class RecordComposeScreen extends StatefulWidget {
  const RecordComposeScreen({super.key});

  @override
  State<RecordComposeScreen> createState() => _RecordComposeScreenState();
}

class _RecordComposeScreenState extends State<RecordComposeScreen> {
  final _storyController = TextEditingController();
  final List<String> _photoPlaceholders = [];
  final Set<String> _selectedGroupIds = {};
  Emotion? _selectedEmotion;
  Place? _selectedPlace;
  bool _isPrivate = false;
  int _photoSequence = 0;

  static const _places = [
    Place(
      id: 'place-yeonnam-cafe',
      name: '연남동 작은 카페',
      latitude: 37.5665,
      longitude: 126.9250,
      address: '서울 마포구 연남동',
    ),
    Place(
      id: 'place-hangang',
      name: '한강공원',
      latitude: 37.5283,
      longitude: 126.9328,
      address: '서울 영등포구 여의도동',
    ),
    Place(
      id: 'place-seongsu',
      name: '성수동',
      latitude: 37.5446,
      longitude: 127.0557,
      address: '서울 성동구 성수동',
    ),
    Place(
      id: 'place-jeju-coast',
      name: '제주 해안 산책로',
      latitude: 33.4996,
      longitude: 126.5312,
      address: '제주특별자치도 제주시',
    ),
  ];

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
    final place = await showModalBottomSheet<Place>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const PlacePickerSheet(places: _places),
    );
    if (place != null) setState(() => _selectedPlace = place);
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

  void _publish() {
    if (_photoPlaceholders.isEmpty) {
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

    setState(() {
      _photoPlaceholders.clear();
      _selectedGroupIds.clear();
      _selectedEmotion = null;
      _selectedPlace = null;
      _isPrivate = false;
      _storyController.clear();
    });
    _showMessage('기록이 작성되었습니다.');
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
            onChanged: _toggleGroup,
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
