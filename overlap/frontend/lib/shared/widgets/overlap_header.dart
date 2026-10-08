import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../features/notification/widgets/notification_bell.dart';

class OverlapHeader extends StatelessWidget implements PreferredSizeWidget {
  const OverlapHeader({
    super.key,
    this.showBackButton = false,
    this.onBack,
    this.onNotifications,
    this.onSaved,
  });

  final bool showBackButton;
  final VoidCallback? onBack;
  final VoidCallback? onNotifications;
  final VoidCallback? onSaved;

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
          child: Stack(
            alignment: Alignment.center,
            children: [
              Center(
                child: RichText(
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
              ),
              if (showBackButton)
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 56,
                    child: IconButton(
                      onPressed: onBack ?? () => Navigator.maybePop(context),
                      icon: const Icon(Icons.arrow_back),
                      tooltip: '뒤로가기',
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onSaved != null)
                      IconButton(
                        onPressed: onSaved,
                        icon: const Icon(Icons.bookmark_border),
                        tooltip: '저장한 장소',
                      ),
                    NotificationBell(onPressed: onNotifications),
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
