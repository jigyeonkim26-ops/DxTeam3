import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/record.dart';
import '../services/record_api.dart';
import '../models/feed_filter.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/group.dart';
import 'record_detail_screen.dart';
import '../widgets/feed_filter_sheet.dart';
import '../widgets/record_card.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({
    super.key,
    this.recordApi,
    this.isActive = true,
    this.initialFilter = FeedFilter.all,
    this.initialGroupId,
    this.showBackButton = false,
  });
  final FeedFilter initialFilter;
  final String? initialGroupId;
  final bool showBackButton;
  final RecordApi? recordApi;
  final bool isActive;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  Set<String> _selectedFilters = {'all'};
  final Set<String> _likedRecordIds = {};
  List<Record> _records = [];
  List<Group> _groups = [];
  bool _isLoading = true;
  String? _error;
  int _generation = 0;
  late final RecordApi _api;

  @override
  void initState() {
    super.initState();
    _selectedFilters = {widget.initialGroupId ?? widget.initialFilter.name};
    _api = widget.recordApi ?? RecordApi();
    RecordApi.revision.addListener(_reload);
    _reload();
  }

  @override
  void didUpdateWidget(covariant FeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) _reload();
  }

  @override
  void dispose() {
    _generation++;
    RecordApi.revision.removeListener(_reload);
    if (widget.recordApi == null) _api.close();
    super.dispose();
  }

  String get _filterLabel {
    if (_selectedFilters.contains('all')) return '내 맞춤 피드';
    if (_selectedFilters.length != 1) return '${_selectedFilters.length}개 선택';
    final filter = _selectedFilters.single;
    if (filter == 'mine') return '내 기록만 보기';
    return _groups.where((g) => g.id == filter).firstOrNull?.name ?? '내 맞춤 피드';
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final groups = await _api.groups();
      if (!mounted || generation != _generation) return;
      _selectedFilters.retainAll({'all', 'mine', ...groups.map((g) => g.id)});
      if (_selectedFilters.isEmpty) _selectedFilters = {'all'};
      final selection = Set<String>.of(_selectedFilters);
      final List<Record> records;
      if (selection.contains('all')) {
        records = await _api.feed();
      } else {
        final batches = await Future.wait([
          for (final filter in selection)
            _api.feed(
              mine: filter == 'mine',
              groupId: filter == 'mine' ? null : filter,
            ),
        ]);
        records = {
          for (final batch in batches)
            for (final record in batch) record.id: record,
        }.values.toList();
      }
      records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!mounted || generation != _generation) return;
      setState(() {
        _records = records;
        _groups = groups;
      });
    } on ApiException catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _records = [];
          _groups = [];
          _error = error.message;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _records = [];
          _groups = [];
          _error = '피드 응답을 읽지 못했습니다.';
        });
      }
    } finally {
      // Only the latest request may finish the visible loading state.
      if (mounted && generation == _generation) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _selectFilter() async {
    final filters = await showModalBottomSheet<Set<String>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) =>
          FeedFilterSheet(selectedFilters: _selectedFilters, groups: _groups),
    );
    if (filters != null && mounted) {
      setState(() => _selectedFilters = Set.of(filters));
      await _reload();
    }
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
    final records = _records;
    return ColoredBox(
      color: AppColors.paper,
      child: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          children: [
            if (widget.showBackButton)
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back, color: AppColors.deepNavy),
                  tooltip: '뒤로가기',
                ),
              ),
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
                label: _filterLabel,
                onTap: _selectFilter,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              TextButton(onPressed: _reload, child: Text('$_error 다시 시도'))
            else if (records.isEmpty)
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
