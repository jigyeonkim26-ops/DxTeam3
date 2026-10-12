import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/network/api_client.dart';
import '../../auth/services/auth_api_service.dart';
import '../../group/models/group_list_item_data.dart';
import '../../group/services/group_list_store.dart';
import '../../memory/screens/record_detail_screen.dart';
import '../../memory/services/record_api.dart';
import '../../memory/widgets/record_card.dart';
import '../../../shared/models/record.dart';
import '../models/profile_summary_data.dart';
import '../models/user_profile.dart';
import '../services/saved_places_api.dart';
import '../widgets/profile_summary_card.dart';
import 'profile_edit_screen.dart';
import 'saved_screen.dart';

enum _ProfileContentTab { feed, savedPlaces }

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    this.onShowMyMap,
    this.recordApi,
    this.savedPlacesApi,
    this.isActive = true,
  });

  final RecordApi? recordApi;
  final SavedPlacesApi? savedPlacesApi;
  final bool isActive;
  final VoidCallback? onShowMyMap;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final RecordApi _api;
  UserProfile? _currentUser;
  List<Record> _myRecords = [];
  bool _isProfileLoading = true;
  bool _isRecordsLoading = true;
  bool _isGroupsLoading = true;
  String? _profileError;
  String? _recordsError;
  String? _groupsError;
  int _generation = 0;
  int _photoRevision = 0;
  _ProfileContentTab _selectedContentTab = _ProfileContentTab.feed;
  final Set<String> _likedRecordIds = {};

  @override
  void initState() {
    super.initState();
    _api = widget.recordApi ?? RecordApi();
    RecordApi.revision.addListener(_reload);
    _reload();
  }

  @override
  void didUpdateWidget(covariant ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) _reload();
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    setState(() {
      _isProfileLoading = true;
      _isRecordsLoading = true;
      _isGroupsLoading = true;
      _profileError = null;
      _recordsError = null;
      _groupsError = null;
    });
    await Future.wait([
      _loadProfile(generation),
      _loadRecords(generation),
      _loadGroups(generation),
    ]);
  }

  Future<void> _loadProfile(int generation) async {
    try {
      final user = await AuthApiService.currentUser();
      if (mounted && generation == _generation) {
        setState(() => _currentUser = user);
      }
    } on ApiException catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _profileError = error.message);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _profileError = '프로필 정보를 불러오지 못했습니다.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _isProfileLoading = false);
      }
    }
  }

  Future<void> _loadRecords(int generation) async {
    try {
      final records = await _api.feed(mine: true);
      records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (mounted && generation == _generation) {
        setState(() => _myRecords = records);
      }
    } on ApiException catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _recordsError = error.message);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _recordsError = '내 기록을 불러오지 못했습니다.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _isRecordsLoading = false);
      }
    }
  }

  Future<void> _loadGroups(int generation) async {
    try {
      await GroupListStore.refreshGroups();
    } on ApiException catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _groupsError = error.message);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _groupsError = '내 모임을 불러오지 못했습니다.');
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _isGroupsLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    RecordApi.revision.removeListener(_reload);
    if (widget.recordApi == null) _api.close();
    super.dispose();
  }

  Future<void> _openRecord(Record record) async {
    final result = await Navigator.of(context).push<RecordDetailResult>(
      MaterialPageRoute<RecordDetailResult>(
        builder: (_) => RecordDetailScreen(
          record: record,
          recordApi: _api,
          canManage: true,
        ),
      ),
    );
    if (!mounted || result == null) return;
    if (result.updatedRecord case final Record updated) {
      setState(() {
        _myRecords = [
          for (final item in _myRecords)
            if (item.id == updated.id) updated else item,
        ];
      });
    } else if (result.deletedRecordId case final String deletedId) {
      setState(() {
        _myRecords = _myRecords.where((item) => item.id != deletedId).toList();
      });
    }
  }

  Future<void> _openProfileEdit() async {
    final user = _currentUser;
    if (user == null) return;
    final updated = await Navigator.of(context).push<ProfileEditResult>(
      MaterialPageRoute<ProfileEditResult>(
        builder: (_) =>
            ProfileEditScreen(profile: user, photoRevision: _photoRevision),
      ),
    );
    if (!mounted || updated == null) return;
    setState(() {
      _currentUser = updated.profile;
      if (updated.photoChanged) _photoRevision++;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('프로필이 수정되었습니다.')));
  }

  void _toggleLike(String recordId) {
    setState(() {
      if (!_likedRecordIds.add(recordId)) _likedRecordIds.remove(recordId);
    });
  }

  ProfileSummaryData _summaryFor(UserProfile user, int groupCount) {
    return ProfileSummaryData(
      userName: user.nickname,
      statusText: '',
      recordCount: _myRecords.length,
      visitedPlaceCount: _myRecords
          .map((record) => record.place.id)
          .toSet()
          .length,
      groupCount: groupCount,
      recentRecordTitle: '',
      recentRecordPlace: '',
    );
  }

  Widget _buildProfileSummary(List<GroupListItemData> groups) {
    if (_isProfileLoading || _isGroupsLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_profileError != null || _groupsError != null) {
      final message = _profileError ?? _groupsError!;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: TextButton(onPressed: _reload, child: Text('$message 다시 시도')),
      );
    }
    final user = _currentUser;
    if (user == null) return const SizedBox.shrink();

    return ProfileSummaryCard(
      profile: _summaryFor(user, groups.length),
      photoRevision: _photoRevision,
      onProfileTap: _openProfileEdit,
      onRecordsTap: () => setState(() {
        _selectedContentTab = _ProfileContentTab.feed;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<GroupListItemData>>(
      valueListenable: GroupListStore.groupsListenable,
      builder: (context, groups, _) {
        return ColoredBox(
          color: AppColors.paper,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            children: [
              const Text(
                'MY PAGE',
                style: TextStyle(
                  color: AppColors.coral,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _buildProfileSummary(groups),
              const SizedBox(height: AppSpacing.md),
              _ProfileContentTabs(
                selectedTab: _selectedContentTab,
                onSelected: (tab) => setState(() => _selectedContentTab = tab),
                onShowMyMap: widget.onShowMyMap ?? () {},
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_selectedContentTab == _ProfileContentTab.feed)
                _buildRecords()
              else
                SavedScreen(
                  embedded: true,
                  isActive: widget.isActive,
                  savedPlacesApi: widget.savedPlacesApi,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRecords() {
    if (_isRecordsLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_recordsError != null) {
      return TextButton(
        onPressed: _reload,
        child: Text('$_recordsError 다시 시도'),
      );
    }
    if (_myRecords.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(
          child: Text(
            '아직 작성한 기록이 없어요.',
            style: TextStyle(color: AppColors.muted),
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final record in _myRecords) ...[
          RecordCard(
            record: record,
            isLiked: _likedRecordIds.contains(record.id),
            onTap: () => _openRecord(record),
            onLikeTap: () => _toggleLike(record.id),
            onCommentTap: () => _openRecord(record),
            onPlaceTap: () {},
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

class _ProfileContentTabs extends StatelessWidget {
  const _ProfileContentTabs({
    required this.selectedTab,
    required this.onSelected,
    required this.onShowMyMap,
  });

  final _ProfileContentTab selectedTab;
  final ValueChanged<_ProfileContentTab> onSelected;
  final VoidCallback onShowMyMap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ProfileContentTabButton(
            icon: Icons.grid_view_rounded,
            label: '내 기록',
            isSelected: selectedTab == _ProfileContentTab.feed,
            onTap: () => onSelected(_ProfileContentTab.feed),
          ),
        ),
        Expanded(
          child: _ProfileContentTabButton(
            icon: Icons.map_outlined,
            label: '내 지도',
            isSelected: false,
            onTap: onShowMyMap,
          ),
        ),
        Expanded(
          child: _ProfileContentTabButton(
            icon: Icons.bookmark_border_rounded,
            label: '저장한 장소',
            isSelected: selectedTab == _ProfileContentTab.savedPlaces,
            onTap: () => onSelected(_ProfileContentTab.savedPlaces),
          ),
        ),
      ],
    );
  }
}

class _ProfileContentTabButton extends StatelessWidget {
  const _ProfileContentTabButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? AppColors.deepNavy : AppColors.muted;
    return Semantics(
      button: true,
      selected: isSelected,
      label: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isSelected ? AppColors.deepNavy : AppColors.divider,
                  width: isSelected ? 2 : 1,
                ),
              ),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
        ),
      ),
    );
  }
}
