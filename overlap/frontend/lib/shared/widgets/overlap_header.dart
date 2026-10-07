import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

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
                width: 56,
                child: showBackButton
                    ? IconButton(
                        onPressed: onBack ?? () => Navigator.maybePop(context),
                        icon: const Icon(Icons.arrow_back),
                        tooltip: '뒤로가기',
                      )
                    : null,
              ),
              const Expanded(
                child: Text(
                  'OVERLAP',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.deepNavy,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
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
