import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../group/models/group_list_item_data.dart';
import '../../group/services/mock_group_repository.dart';
import '../../memory/models/feed_filter.dart';
import '../../memory/screens/feed_screen.dart';
import '../../notification/screens/notification_settings_screen.dart';
import '../../notification/screens/notifications_screen.dart';
import '../services/mock_profile_repository.dart';
import '../widgets/profile_menu_item.dart';
import '../widgets/profile_summary_card.dart';
import 'group_management_screen.dart';
import 'profile_edit_screen.dart';
import 'saved_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _profileImagePath;

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

  void _openMyRecords() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(
          body: SafeArea(
            child: FeedScreen(
              initialFilter: FeedFilter.mine,
              showBackButton: true,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<GroupListItemData>>(
      valueListenable: MockGroupRepository.groupsListenable,
      builder: (context, groups, _) {
        final profile = MockProfileRepository.profile.copyWith(
          groupCount: groups.length,
        );
        return ColoredBox(
          color: AppColors.paper,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'MY PAGE',
                      style: TextStyle(
                        color: AppColors.coral,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const SavedScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.bookmark_border),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const NotificationsScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.notifications_none),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              ProfileSummaryCard(
                profile: profile,
                profileImagePath: _profileImagePath,
                onProfileTap: _openProfileEdit,
                onRecordsTap: _openMyRecords,
              ),
              const SizedBox(height: AppSpacing.lg),
              ProfileMenuItem(
                title: '내 모임 관리',
                description: groups.isEmpty
                    ? '참여 중인 모임이 없어요'
                    : '${groups.first.name} 외 ${profile.groupCount - 1}개',
                icon: Icons.groups_outlined,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const GroupManagementScreen(),
                  ),
                ),
              ),
              ProfileMenuItem(
                title: '실시간 알림',
                description: '댓글 · 새 기록 · 모임 소식',
                icon: Icons.notifications_outlined,
                badge: '2',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const NotificationsScreen(),
                  ),
                ),
              ),
              ProfileMenuItem(
                title: '알림 설정',
                description: '장소 근처 리마인드와 방해 금지 시간',
                icon: Icons.settings_outlined,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const NotificationSettingsScreen(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
