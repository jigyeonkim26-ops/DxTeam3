import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';

class JoinGroupScreen extends StatelessWidget {
  const JoinGroupScreen({super.key, required this.inviteCode});

  final String inviteCode;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('모임 참여')),
      body: const SafeArea(
        top: false,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.group_outlined, size: 42, color: AppColors.muted),
                SizedBox(height: AppSpacing.sm),
                Text(
                  '초대 정보를 불러올 수 없어요.',
                  style: TextStyle(
                    color: AppColors.deepNavy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: AppSpacing.xxs),
                Text(
                  '모임 API가 연결되면 초대 코드를 확인할 수 있어요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
