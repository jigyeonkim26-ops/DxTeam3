import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../group/models/group_list_item_data.dart';
import '../../group/services/mock_group_repository.dart';
import '../../memory/widgets/record_card.dart';
import '../services/mock_profile_repository.dart';
import '../services/mock_saved_repository.dart';
import '../widgets/profile_summary_card.dart';
import '../widgets/saved_item_row.dart';
import 'profile_edit_screen.dart';

enum _ProfileContentTab { feed, savedPlaces }

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.onShowMyMap});

  final VoidCallback? onShowMyMap;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _profileImagePath;
  _ProfileContentTab _selectedContentTab = _ProfileContentTab.feed;
  final Set<String> _likedRecordIds = {};

  void _show(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _openProfileEdit() async {
    final result = await Navigator.of(context).push<ProfileEditResult>(
      MaterialPageRoute<ProfileEditResult>(
        builder: (_) =>
            ProfileEditScreen(initialProfileImagePath: _profileImagePath),
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _profileImagePath = result.profileImagePath);
    _show(context, '프로필이 수정되었어요.');
  }

  void _showMyFeed() {
    setState(() => _selectedContentTab = _ProfileContentTab.feed);
  }

  void _toggleLike(String recordId) {
    setState(() {
      if (!_likedRecordIds.add(recordId)) {
        _likedRecordIds.remove(recordId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<GroupListItemData>>(
      valueListenable: MockGroupRepository.groupsListenable,
      builder: (context, groups, _) {
        final profile = MockProfileRepository.profile.copyWith(
          groupCount: groups.length,
        );
        const myRecords = <dynamic>[];
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
              ProfileSummaryCard(
                profile: profile,
                profileImagePath: _profileImagePath,
                onProfileTap: _openProfileEdit,
                onRecordsTap: _showMyFeed,
              ),
              const SizedBox(height: AppSpacing.md),
              _ProfileContentTabs(
                selectedTab: _selectedContentTab,
                onSelected: (tab) => setState(() => _selectedContentTab = tab),
                onShowMyMap: widget.onShowMyMap ?? () {},
              ),
              const SizedBox(height: AppSpacing.sm),
              if (_selectedContentTab == _ProfileContentTab.feed) ...[
                if (myRecords.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                    child: Center(
                      child: Text(
                        '아직 남긴 기록이 없어요.',
                        style: TextStyle(color: AppColors.muted),
                      ),
                    ),
                  )
                else
                  for (final record in myRecords) ...[
                    RecordCard(
                      record: record,
                      isLiked: _likedRecordIds.contains(record.id),
                      onTap: () => _show(context, '기록 상세 연결은 추후 적용됩니다.'),
                      onLikeTap: () => _toggleLike(record.id),
                      onCommentTap: () => _show(context, '기록 상세 연결은 추후 적용됩니다.'),
                      onPlaceTap: () => _show(context, '장소 상세 연결은 추후 적용됩니다.'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
              ] else if (MockSavedRepository.wishPlaces.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                  child: Center(
                    child: Text(
                      '저장한 장소가 없어요.',
                      style: TextStyle(color: AppColors.muted),
                    ),
                  ),
                )
              else
                for (final item in MockSavedRepository.wishPlaces)
                  SavedItemRow(
                    item: item,
                    onTap: () => _show(context, '장소 상세 연결은 추후 적용됩니다.'),
                  ),
            ],
          ),
        );
      },
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
            label: '내 피드',
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
