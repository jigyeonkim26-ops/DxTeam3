import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';

class ShareCardScreen extends StatelessWidget {
  const ShareCardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('공유 카드')),
      body: const SafeArea(
        top: false,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.image_outlined, color: AppColors.muted, size: 42),
                SizedBox(height: AppSpacing.sm),
                Text(
                  '공유할 기록을 선택해 주세요.',
                  style: TextStyle(
                    color: AppColors.deepNavy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: AppSpacing.xxs),
                Text(
                  '기록 데이터가 준비되면 공유 카드를 만들 수 있어요.',
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
