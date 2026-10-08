import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/record.dart';
import '../../memory/screens/record_detail_screen.dart';
import '../../memory/services/record_api.dart';
import '../../memory/widgets/record_card.dart';
import '../../user/services/saved_places_api.dart';

class PlaceDetailScreen extends StatefulWidget {
  const PlaceDetailScreen({
    super.key,
    required this.placeId,
    required this.name,
    required this.address,
    required this.recordCount,
    this.recordApi,
    this.savedPlacesApi,
  });

  final String placeId;
  final String name;
  final String? address;
  final int recordCount;
  final RecordApi? recordApi;
  final SavedPlacesApi? savedPlacesApi;

  @override
  State<PlaceDetailScreen> createState() => _PlaceDetailScreenState();
}

class _PlaceDetailScreenState extends State<PlaceDetailScreen> {
  late final RecordApi _recordApi;
  late final SavedPlacesApi _savedPlacesApi;
  List<Record> _records = const [];
  bool _isLoadingRecords = true;
  bool _hasRecordLoadError = false;
  bool _isSaved = false;
  bool _isLoadingSavedState = true;
  bool _isSaving = false;

  int? get _placeId {
    final placeId = int.tryParse(widget.placeId);
    return placeId != null && placeId > 0 ? placeId : null;
  }

  @override
  void initState() {
    super.initState();
    _recordApi = widget.recordApi ?? RecordApi();
    _savedPlacesApi = widget.savedPlacesApi ?? SavedPlacesApi();
    _loadRecords();
    _loadSavedState();
  }

  Future<void> _loadRecords() async {
    final placeId = _placeId;
    if (placeId == null) {
      if (!mounted) return;
      setState(() {
        _isLoadingRecords = false;
        _hasRecordLoadError = true;
      });
      return;
    }

    setState(() {
      _isLoadingRecords = true;
      _hasRecordLoadError = false;
    });
    try {
      final records = await _recordApi.feed(placeId: placeId);
      if (!mounted) return;
      setState(() {
        _records = records;
        _isLoadingRecords = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() {
        _isLoadingRecords = false;
        _hasRecordLoadError = true;
      });
    }
  }

  Future<void> _loadSavedState() async {
    final placeId = _placeId;
    if (placeId == null) {
      if (mounted) setState(() => _isLoadingSavedState = false);
      return;
    }
    try {
      final state = await _savedPlacesApi.state(placeId);
      if (!mounted) return;
      setState(() {
        _isSaved = state.saved;
        _isLoadingSavedState = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() => _isLoadingSavedState = false);
    }
  }

  Future<void> _toggleSaved() async {
    final placeId = _placeId;
    if (placeId == null || _isSaving || _isLoadingSavedState) return;

    setState(() => _isSaving = true);
    try {
      final state = _isSaved
          ? await _savedPlacesApi.unsave(placeId)
          : await _savedPlacesApi.save(placeId);
      if (!mounted) return;
      setState(() => _isSaved = state.saved);
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _openRecordDetail(Record record) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => RecordDetailScreen(record: record)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ColoredBox(
        color: AppColors.paper,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.lg,
          ),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back),
                  tooltip: '뒤로가기',
                ),
                const SizedBox(width: AppSpacing.xxs),
                const Expanded(
                  child: Text(
                    '장소 상세',
                    style: TextStyle(
                      color: AppColors.deepNavy,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _isSaving || _isLoadingSavedState
                      ? null
                      : _toggleSaved,
                  icon: _isSaving || _isLoadingSavedState
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _isSaved ? Icons.bookmark : Icons.bookmark_border,
                          color: _isSaved ? AppColors.coral : AppColors.deepNavy,
                        ),
                  tooltip: _isSaved ? '저장 취소' : '장소 저장',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _PlaceSummary(
              name: widget.name,
              address: widget.address,
              recordCount: widget.recordCount,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '이 장소에 쌓인 기억',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.deepNavy,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '친구들이 같은 장소에서 보낸 시간들이에요.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.muted,
                fontSize: 14,
                fontWeight: FontWeight.w400,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_isLoadingRecords)
              const Center(child: CircularProgressIndicator())
            else if (_hasRecordLoadError)
              Center(
                child: TextButton(
                  onPressed: _loadRecords,
                  child: const Text('기록을 불러오지 못했습니다. 다시 시도'),
                ),
              )
            else if (_records.isEmpty)
              const Center(child: Text('이 장소에 아직 기록이 없어요.'))
            else
              for (final record in _records) ...[
                RecordCard(
                  record: record,
                  isLiked: false,
                  onTap: () => _openRecordDetail(record),
                  onLikeTap: () {},
                  onCommentTap: () => _openRecordDetail(record),
                  onPlaceTap: () {},
                ),
                const SizedBox(height: AppSpacing.md),
              ],
          ],
        ),
      ),
    );
  }
}

class _PlaceSummary extends StatelessWidget {
  const _PlaceSummary({
    required this.name,
    required this.address,
    required this.recordCount,
  });

  final String name;
  final String? address;
  final int recordCount;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'OVERLAPPED PLACE',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              name,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 17),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: Text(
                    address ?? '주소 정보 없음',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _SummaryChip(
              icon: Icons.auto_stories_outlined,
              label: '기록 $recordCount개',
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: AppColors.paleMint,
        borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.deepNavy),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.deepNavy,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
