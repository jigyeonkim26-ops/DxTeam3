import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/record.dart';
import '../../memory/screens/record_detail_screen.dart';
import '../../memory/services/record_api.dart';
import '../../memory/widgets/record_card.dart';

/// 선택한 장소에 쌓인 기록을 보여주는 상세 화면입니다.
class PlaceDetailScreen extends StatefulWidget {
  const PlaceDetailScreen({
    super.key,
    required this.placeId,
    required this.name,
    required this.address,
    required this.recordCount,
    this.recordApi,
  });

  final String placeId;
  final String name;
  final String? address;
  final int recordCount;
  final RecordApi? recordApi;

  @override
  State<PlaceDetailScreen> createState() => _PlaceDetailScreenState();
}

class _PlaceDetailScreenState extends State<PlaceDetailScreen> {
  bool _isSaved = false;
  late final RecordApi _recordApi;
  List<Record> _records = const [];
  bool _isLoadingRecords = true;
  bool _hasRecordLoadError = false;

  @override
  void initState() {
    super.initState();
    _recordApi = widget.recordApi ?? RecordApi();
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    final placeId = int.tryParse(widget.placeId);
    if (placeId == null || placeId <= 0) {
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
                  onPressed: () => setState(() => _isSaved = !_isSaved),
                  icon: Icon(
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
              isSaved: _isSaved,
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
    required this.isSaved,
  });

  final String name;
  final String? address;
  final int recordCount;
  final bool isSaved;

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
            Container(
              height: 126,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF9FC4B2), AppColors.deepNavy],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
              ),
              child: const Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.sm),
                  child: Text(
                    '창가 자리와 어울리는 오후',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                _SummaryChip(
                  icon: Icons.auto_stories_outlined,
                  label: '기록 $recordCount개',
                ),
                const SizedBox(width: AppSpacing.xs),
                _SummaryChip(
                  icon: isSaved ? Icons.bookmark : Icons.bookmark_border,
                  label: isSaved ? '저장됨' : '저장하기',
                ),
              ],
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
