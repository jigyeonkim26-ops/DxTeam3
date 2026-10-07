import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/record.dart';
import '../services/record_api.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/group.dart';
import 'record_detail_screen.dart';
import '../widgets/feed_filter_sheet.dart';
import '../widgets/record_card.dart';

class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key, this.recordApi, this.isActive = true});
  final RecordApi? recordApi;
  final bool isActive;

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  String _selectedFilter = 'all';
  List<Record> _records = [];
  List<Group> _groups = [];
  bool _isLoading = true;
  String? _error;
  int _generation = 0;
  late final RecordApi _api;

  @override
  void initState() {
    super.initState();
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

  String get _filterLabel => _selectedFilter == 'all'
      ? '내 맞춤 피드'
      : _selectedFilter == 'mine'
      ? '내 기록만 보기'
      : _groups.where((g) => g.id == _selectedFilter).firstOrNull?.name ??
            '내 맞춤 피드';

  Future<void> _reload() async {
    final generation = ++_generation;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final groups = await _api.groups();
      if (!mounted || generation != _generation) return;
      if (_selectedFilter != 'all' &&
          _selectedFilter != 'mine' &&
          !groups.any((g) => g.id == _selectedFilter)) {
        _selectedFilter = 'all';
      }
      final records = await _api.feed(
        mine: _selectedFilter == 'mine',
        groupId: _selectedFilter == 'all' || _selectedFilter == 'mine'
            ? null
            : _selectedFilter,
      );
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
    final filter = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          FeedFilterSheet(selectedFilter: _selectedFilter, groups: _groups),
    );
    if (filter != null && mounted) {
      setState(() => _selectedFilter = filter);
      await _reload();
    }
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
                  isLiked: false,
                  onTap: () => _openRecordDetail(record),
                  onLikeTap: () => _showMessage('공감 기능은 준비 중입니다.'),
                  onCommentTap: () => _showMessage('댓글 기능은 준비 중입니다.'),
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
