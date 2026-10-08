import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';

/// Main-map search has no local sample catalog. Record composition uses the
/// Kakao Places search flow instead.
class PlaceSearchScreen extends StatelessWidget {
  const PlaceSearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: const Text('장소 검색')),
      body: const SafeArea(
        top: false,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.search_off_outlined,
                  size: 42,
                  color: AppColors.muted,
                ),
                SizedBox(height: AppSpacing.sm),
                Text(
                  '검색 결과가 없어요.',
                  style: TextStyle(
                    color: AppColors.deepNavy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: AppSpacing.xxs),
                Text(
                  '장소 검색 데이터가 연결되면 결과를 보여드릴게요.',
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
