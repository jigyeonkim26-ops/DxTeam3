import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../services/mock_profile_repository.dart';
import '../widgets/profile_menu_item.dart';
import '../widgets/profile_summary_card.dart';
import '../../notification/screens/notifications_screen.dart';
import '../../notification/screens/notification_settings_screen.dart';
import 'saved_screen.dart';
import 'share_card_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  void _show(BuildContext context, String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    final profile = MockProfileRepository.profile;
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
                  MaterialPageRoute<void>(builder: (_) => const SavedScreen()),
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
          ProfileSummaryCard(profile: profile),
          const SizedBox(height: AppSpacing.lg),
          Text(
            '내 기록',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          ProfileMenuItem(
            title: profile.recentRecordTitle,
            description: profile.recentRecordPlace,
            icon: Icons.coffee_outlined,
            onTap: () => _show(context, '기록 상세 기능은 다음 단계에서 연결됩니다.'),
          ),
          const SizedBox(height: AppSpacing.lg),
          ProfileMenuItem(
            title: '내 모임 관리',
            description: '연남 산책단 외 ${profile.groupCount - 1}개',
            icon: Icons.groups_outlined,
            onTap: () => _show(context, '내 모임 관리 기능은 다음 단계에서 연결됩니다.'),
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
          ProfileMenuItem(
            title: '공유 및 개인정보',
            description: '공유 허용 범위 관리',
            icon: Icons.privacy_tip_outlined,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ShareCardScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
