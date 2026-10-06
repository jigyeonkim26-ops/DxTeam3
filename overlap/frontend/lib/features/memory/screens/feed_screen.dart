import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/record.dart';
import '../data/mock_feed_data.dart';
import '../models/feed_filter.dart';
import 'record_detail_screen.dart';
import '../widgets/feed_filter_sheet.dart';
import '../widgets/record_card.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  FeedFilter _selectedFilter = FeedFilter.all;
  final Set<String> _likedRecordIds = {};

  List<Record> get _visibleRecords {
    final records = switch (_selectedFilter) {
      FeedFilter.all => mockFeedRecords,
      FeedFilter.mine =>
        mockFeedRecords
            .where((record) => record.author.id == currentFeedUser.id)
            .toList(),
      final filter =>
        mockFeedRecords
            .where(
              (record) => record.sharedGroups.any(
                (group) => group.id == _groupIdForFilter(filter),
              ),
            )
            .toList(),
    };
    return [...records]
      ..sort((first, second) => second.createdAt.compareTo(first.createdAt));
  }

  String _groupIdForFilter(FeedFilter filter) => switch (filter) {
    FeedFilter.yeonnam => yeonnamGroup.id,
    FeedFilter.neighborhood => neighborhoodGroup.id,
    FeedFilter.travel => travelGroup.id,
    FeedFilter.all || FeedFilter.mine => '',
  };

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _selectFilter() async {
    final filter = await showModalBottomSheet<FeedFilter>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => FeedFilterSheet(selectedFilter: _selectedFilter),
    );
    if (filter != null) setState(() => _selectedFilter = filter);
  }

  void _toggleLike(String recordId) {
    setState(() {
      if (!_likedRecordIds.add(recordId)) _likedRecordIds.remove(recordId);
    });
  }

  void _openRecordDetail(Record record) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecordDetailScreen(record: record),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final records = _visibleRecords;
    return ColoredBox(
      color: AppColors.paper,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        children: [
          const Text(
            '피드',
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          const Text(
            '함께 남긴 장소의 기억을 모아 봐요.',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: _FeedFilterButton(
              label: _selectedFilter.label,
              onTap: _selectFilter,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (records.isEmpty)
            const _EmptyFeed()
          else
            for (final record in records) ...[
              RecordCard(
                record: record,
                isLiked: _likedRecordIds.contains(record.id),
                onTap: () => _openRecordDetail(record),
                onLikeTap: () => _toggleLike(record.id),
                onCommentTap: () => _openRecordDetail(record),
                onPlaceTap: () => _showMessage('장소 상세는 추후 연결됩니다.'),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
        ],
      ),
    );
  }
}

class _FeedFilterButton extends StatelessWidget {
  const _FeedFilterButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.paleMint,
      borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              const Icon(Icons.keyboard_arrow_down, color: AppColors.deepNavy),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: AppSpacing.xl),
      child: Center(
        child: Text('표시할 기록이 없어요.', style: TextStyle(color: AppColors.muted)),
      ),
    );
  }
}
