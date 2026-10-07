import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_spacing.dart';

class OverlapHeader extends StatelessWidget implements PreferredSizeWidget {
  const OverlapHeader({
    super.key,
    this.showBackButton = false,
    this.onBack,
    this.onSaved,
    this.onNotifications,
  });

  final bool showBackButton;
  final VoidCallback? onBack;
  final VoidCallback? onSaved;
  final VoidCallback? onNotifications;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.paper,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: preferredSize.height,
          child: Row(
            children: [
              SizedBox(
                width: showBackButton ? 56 : AppSpacing.md,
                child: showBackButton
                    ? IconButton(
                        onPressed: onBack ?? () => Navigator.maybePop(context),
                        icon: const Icon(Icons.arrow_back),
                        tooltip: '뒤로가기',
                      )
                    : null,
              ),
              RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                  children: [
                    TextSpan(
                      text: 'OVER',
                      style: TextStyle(color: AppColors.deepNavy),
                    ),
                    TextSpan(
                      text: 'LAP',
                      style: TextStyle(color: AppColors.coral),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 112,
                child: Row(
                  children: [
                    IconButton(
                      onPressed: onSaved,
                      icon: const Icon(Icons.favorite_border),
                      tooltip: '저장',
                    ),
                    IconButton(
                      onPressed: onNotifications,
                      icon: const Icon(Icons.notifications_none),
                      tooltip: '알림',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
