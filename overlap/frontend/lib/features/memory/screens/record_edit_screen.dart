import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/emotion.dart';
import '../../../shared/models/group.dart';
import '../../../shared/models/record.dart';
import '../services/record_api.dart';
import '../widgets/emotion_picker.dart';
import '../widgets/group_picker.dart';

/// Edits only the fields supported by PATCH /records/{record_id}.
/// The existing place and photos remain attached to the record unchanged.
class RecordEditScreen extends StatefulWidget {
  const RecordEditScreen({
    super.key,
    required this.record,
    required this.recordApi,
  });

  final Record record;
  final RecordApi recordApi;

  @override
  State<RecordEditScreen> createState() => _RecordEditScreenState();
}

class _RecordEditScreenState extends State<RecordEditScreen> {
  late final TextEditingController _contentController;
  late Emotion _selectedEmotion;
  late bool _isPrivate;
  late final Set<String> _selectedGroupIds;
  List<Group> _groups = const [];
  bool _isLoadingGroups = true;
  bool _isSaving = false;
  String? _groupError;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(text: widget.record.content);
    _selectedEmotion = widget.record.emotion;
    _isPrivate = widget.record.isPrivate;
    _selectedGroupIds = {
      for (final group in widget.record.sharedGroups) group.id,
    };
    _loadGroups();
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _loadGroups() async {
    setState(() {
      _isLoadingGroups = true;
      _groupError = null;
    });
    try {
      final groups = await widget.recordApi.groups();
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _isLoadingGroups = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _groupError = error.message;
        _isLoadingGroups = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _groupError = '가입한 모임을 불러오지 못했습니다.';
        _isLoadingGroups = false;
      });
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _togglePrivate(bool isPrivate) {
    setState(() {
      _isPrivate = isPrivate;
      if (isPrivate) _selectedGroupIds.clear();
    });
  }

  void _toggleGroup(Group group) {
    setState(() {
      if (!_selectedGroupIds.add(group.id)) _selectedGroupIds.remove(group.id);
    });
  }

  void _toggleAllGroups(bool selected) {
    setState(() {
      if (selected) {
        _selectedGroupIds.addAll(_groups.map((group) => group.id));
      } else {
        _selectedGroupIds.clear();
      }
    });
  }

  bool get _areAllGroupsSelected =>
      _groups.isNotEmpty &&
      _groups.every((group) => _selectedGroupIds.contains(group.id));

  Future<void> _save() async {
    if (_isSaving) return;
    if (!_isPrivate && _isLoadingGroups) {
      _showMessage('가입한 모임을 불러온 뒤 공유 범위를 선택해 주세요.');
      return;
    }
    if (!_isPrivate && _groupError != null) {
      _showMessage('모임 목록을 불러온 뒤 다시 시도해 주세요.');
      return;
    }
    if (!_isPrivate && _selectedGroupIds.isEmpty) {
      _showMessage('공유할 모임을 하나 이상 선택해 주세요.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final updated = await widget.recordApi.update(
        recordId: widget.record.id,
        content: _contentController.text,
        emotion: _selectedEmotion,
        isPrivate: _isPrivate,
        groupIds: _selectedGroupIds,
      );
      if (!mounted) return;
      Navigator.of(context).pop(updated);
    } on ApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } catch (_) {
      if (mounted) _showMessage('기록을 수정하지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.xl,
          ),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: _isSaving
                      ? null
                      : () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back),
                  tooltip: '뒤로가기',
                ),
                const SizedBox(width: AppSpacing.xxs),
                const Expanded(
                  child: Text(
                    '기록 수정',
                    style: TextStyle(
                      color: AppColors.deepNavy,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: ListTile(
                leading: const Icon(Icons.location_on_outlined),
                title: Text(widget.record.place.name),
                subtitle: const Text('장소와 사진은 수정하지 않고 기존 기록을 유지합니다.'),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              '이 순간을 한 줄로',
              style: TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextField(
              controller: _contentController,
              enabled: !_isSaving,
              minLines: 4,
              maxLines: 6,
              maxLength: 300,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: '짧은 기억을 남겨보세요.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              '오늘의 감정',
              style: TextStyle(
                color: AppColors.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            IgnorePointer(
              ignoring: _isSaving,
              child: EmotionPicker(
                selectedEmotion: _selectedEmotion,
                onSelected: (emotion) =>
                    setState(() => _selectedEmotion = emotion),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Card(
              child: SwitchListTile.adaptive(
                value: _isPrivate,
                onChanged: _isSaving ? null : _togglePrivate,
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
                const Expanded(
                  child: Text(
                    '공유할 모임',
                    style: TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
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
                onPressed: _isSaving ? null : _loadGroups,
                child: Text('$_groupError 다시 시도'),
              ),
            if (!_isLoadingGroups &&
                _groupError == null &&
                _groups.isEmpty &&
                !_isPrivate)
              const Text('가입한 모임이 없습니다. 나만 보기로만 저장할 수 있어요.'),
            IgnorePointer(
              ignoring: _isSaving,
              child: GroupPicker(
                groups: _groups,
                selectedGroupIds: _selectedGroupIds,
                isDisabled: _isPrivate,
                areAllSelected: _areAllGroupsSelected,
                onChanged: _toggleGroup,
                onSelectAll: _toggleAllGroups,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                key: const Key('record-edit-save'),
                onPressed: _isSaving ? null : _save,
                child: Text(_isSaving ? '저장 중...' : '수정 저장'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
