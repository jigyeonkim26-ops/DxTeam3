import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/record.dart';
import '../../ai/models/ai_place_recommendation.dart';
import '../../memory/screens/record_detail_screen.dart';
import '../../memory/services/record_api.dart';
import '../../memory/services/record_likes_api.dart';
import '../../memory/widgets/record_card.dart';
import '../../user/services/saved_places_api.dart';

class PlaceDetailScreen extends StatefulWidget {
  const PlaceDetailScreen({
    super.key,
    required this.placeId,
    required this.name,
    required this.address,
    required this.recordCount,
    this.sourceGroupId,
    this.recordApi,
    this.savedPlacesApi,
    this.recommendation,
  });

  final String placeId;
  final String name;
  final String? address;
  final int recordCount;
  final String? sourceGroupId;
  final RecordApi? recordApi;
  final SavedPlacesApi? savedPlacesApi;
  final AiPlaceRecommendation? recommendation;

  @override
  State<PlaceDetailScreen> createState() => _PlaceDetailScreenState();
}

class _PlaceDetailScreenState extends State<PlaceDetailScreen> {
  late final RecordApi _recordApi;
  late final SavedPlacesApi _savedPlacesApi;
  List<Record> _records = const [];
  Map<String, RecordLikeState> _likeStates = const {};
  final Set<String> _likeRequestsInProgress = {};
  bool _isLoadingRecords = true;
  bool _hasRecordLoadError = false;
  bool _isSaved = false;
  bool _isLoadingSavedState = true;
  bool _isSaving = false;
  bool _lookupFailed = false;
  int? _resolvedPlaceId;
  int? _actualRecordCount;

  int? get _placeId => _resolvedPlaceId;

  @override
  void initState() {
    super.initState();
    _recordApi = widget.recordApi ?? RecordApi();
    _savedPlacesApi = widget.savedPlacesApi ?? SavedPlacesApi();
    final initialId = int.tryParse(widget.placeId);
    _resolvedPlaceId = initialId != null && initialId > 0 ? initialId : null;
    _actualRecordCount = widget.recommendation == null ? widget.recordCount : null;
    if (widget.recommendation != null) {
      _loadKakaoState();
    } else {
      _loadRecords();
      _loadSavedState();
    }
  }

  Future<void> _loadKakaoState() async {
    final kakaoId = widget.recommendation?.kakaoPlaceId;
    if (kakaoId == null) {
      if (mounted) {
        setState(() {
          _lookupFailed = true;
          _isLoadingSavedState = false;
          _isLoadingRecords = false;
        });
      }
      return;
    }
    setState(() {
      _lookupFailed = false;
      _isLoadingSavedState = true;
    });
    try {
      final lookup = await _savedPlacesApi.lookupKakao(kakaoId);
      if (!mounted) return;
      setState(() {
        _resolvedPlaceId = lookup.placeId;
        _actualRecordCount = lookup.recordCount;
        _isSaved = lookup.saved;
        _isLoadingSavedState = false;
      });
      if (lookup.placeId != null) {
        _loadRecords();
      } else {
        setState(() => _isLoadingRecords = false);
      }
    } on ApiException {
      if (!mounted) return;
      setState(() {
        _lookupFailed = true;
        _isLoadingSavedState = false;
        _isLoadingRecords = false;
      });
    }
  }

  Future<void> _loadRecords() async {
    final placeId = _placeId;
    if (placeId == null) {
      if (!mounted) return;
      setState(() {
        _isLoadingRecords = false;
        _records = const [];
        _hasRecordLoadError = widget.recommendation == null;
      });
      return;
    }

    setState(() {
      _isLoadingRecords = true;
      _hasRecordLoadError = false;
    });
    try {
      final records = await _recordApi.feed(
        placeId: placeId,
        groupId: widget.sourceGroupId,
      );
      final likeStates = await _loadLikeStates(records);
      if (!mounted) return;
      setState(() {
        _records = records;
        _likeStates = likeStates;
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

  Future<Map<String, RecordLikeState>> _loadLikeStates(
    List<Record> records,
  ) async {
    final recordsById = {for (final record in records) record.id: record};
    final entries = await Future.wait(
      recordsById.entries.map((entry) async {
        try {
          return MapEntry(entry.key, await RecordLikesApi.getState(entry.key));
        } on ApiException {
          return MapEntry(
            entry.key,
            _likeStates[entry.key] ??
                RecordLikeState(likeCount: entry.value.likeCount, liked: false),
          );
        }
      }),
    );
    return Map<String, RecordLikeState>.fromEntries(entries);
  }

  RecordLikeState _likeStateFor(Record record) =>
      _likeStates[record.id] ??
      RecordLikeState(likeCount: record.likeCount, liked: false);

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleLike(String recordId) async {
    if (_likeRequestsInProgress.contains(recordId)) return;
    final previous = _likeStates[recordId];
    if (previous == null) return;

    setState(() => _likeRequestsInProgress.add(recordId));
    try {
      final next = previous.liked
          ? await RecordLikesApi.unlike(recordId)
          : await RecordLikesApi.like(recordId);
      if (mounted) {
        setState(() => _likeStates = {..._likeStates, recordId: next});
      }
    } on ApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _likeRequestsInProgress.remove(recordId));
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
    final recommendation = widget.recommendation;
    if (_isSaving || _isLoadingSavedState || _lookupFailed ||
        (placeId == null &&
            (recommendation?.kakaoPlaceId == null || recommendation?.address == null))) {
      return;
    }

    setState(() => _isSaving = true);
    try {
      final state = _isSaved
          ? await _savedPlacesApi.unsave(placeId!)
          : placeId != null
          ? await _savedPlacesApi.save(placeId)
          : await _savedPlacesApi.saveKakao(recommendation!.kakaoPlaceId!,
              name: recommendation.name, address: recommendation.address!);
      if (!mounted) return;
      setState(() {
        _resolvedPlaceId = state.placeId;
        _isSaved = state.saved;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _openRecordDetail(Record record) async {
    final commentGroupId = widget.sourceGroupId ?? record.commentContextGroupId;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            RecordDetailScreen(record: record, commentGroupId: commentGroupId),
      ),
    );
    if (!mounted) return;
    try {
      final state = await RecordLikesApi.getState(record.id);
      if (mounted) {
        setState(() => _likeStates = {..._likeStates, record.id: state});
      }
    } on ApiException {
      // Record detail already presents errors; retain the last confirmed state.
    }
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
                  onPressed: _isSaving || _isLoadingSavedState || _lookupFailed ||
                          (widget.recommendation != null &&
                              (widget.recommendation!.kakaoPlaceId == null ||
                               widget.recommendation!.address == null))
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
                          color: _isSaved
                              ? AppColors.coral
                              : AppColors.deepNavy,
                        ),
                  tooltip: _isSaved ? '저장 취소' : '장소 저장',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _PlaceSummary(
              name: widget.name,
              address: widget.address,
              recordCount: _actualRecordCount,
              isAiRecommendation: widget.recommendation != null,
            ),
            if (_lookupFailed)
              TextButton(
                onPressed: _loadKakaoState,
                child: const Text('장소 정보를 불러오지 못했습니다. 다시 시도'),
              ),
            if (widget.recommendation != null) ...[
              const SizedBox(height: AppSpacing.md),
              _AiRecommendationSummary(recommendation: widget.recommendation!),
            ],
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
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Center(
                  child: Text(
                    '이 장소에 아직 기록이 없어요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 14,
                      fontWeight: FontWeight.normal,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              )
            else
              for (final record in _records) ...[
                RecordCard(
                  record: record,
                  isLiked: _likeStateFor(record).liked,
                  likeCount: _likeStateFor(record).likeCount,
                  isLikeLoading: _likeRequestsInProgress.contains(record.id),
                  onTap: () => _openRecordDetail(record),
                  onLikeTap: () => _toggleLike(record.id),
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
    required this.isAiRecommendation,
  });

  final String name;
  final String? address;
  final int? recordCount;
  final bool isAiRecommendation;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isAiRecommendation ? 'AI 추천 장소' : 'OVERLAPPED PLACE',
              style: const TextStyle(
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
            if (recordCount != null && (!isAiRecommendation || recordCount! > 0)) ...[
              const SizedBox(height: AppSpacing.md),
              _SummaryChip(
                icon: Icons.auto_stories_outlined,
                label: '기록 $recordCount개',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AiRecommendationSummary extends StatelessWidget {
  const _AiRecommendationSummary({required this.recommendation});

  final AiPlaceRecommendation recommendation;

  @override
  Widget build(BuildContext context) => Card(
    color: AppColors.surface,
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('AI 추천 이유', style: TextStyle(
            color: AppColors.deepNavy, fontSize: 16, fontWeight: FontWeight.w700,
          )),
          const SizedBox(height: AppSpacing.sm),
          Text(recommendation.reason, style: const TextStyle(color: AppColors.muted)),
          if (recommendation.matchedKeywords.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final keyword in recommendation.matchedKeywords)
                  _SummaryChip(icon: Icons.auto_awesome, label: keyword),
              ],
            ),
          ],
        ],
      ),
    ),
  );
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
