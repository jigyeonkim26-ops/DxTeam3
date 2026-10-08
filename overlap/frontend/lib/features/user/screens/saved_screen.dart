import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../services/mock_saved_repository.dart';
import '../widgets/saved_item_row.dart';

class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final items = MockSavedRepository.wishPlaces;
    return Scaffold(
      appBar: AppBar(title: const Text('저장한 장소')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          children: [
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(child: Text('저장한 장소가 없어요.')),
              ),
            ...items.map(
              (item) => SavedItemRow(
                item: item,
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('장소 상세 연결은 추후 적용됩니다.')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
