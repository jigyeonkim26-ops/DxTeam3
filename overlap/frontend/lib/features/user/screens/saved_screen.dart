import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../models/saved_item_data.dart';
import '../../memory/screens/feed_screen.dart';
import '../../memory/models/feed_filter.dart';
import '../widgets/saved_tab_bar.dart';

class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key});
  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  SavedItemType _selectedType = SavedItemType.wishPlace;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('저장한 장소')),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              child: Column(
                children: [
                  Text(
                    '나중에 만나고 싶은 장소',
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontSize: 27, height: 1.25),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '가보고 싶은 곳과 내가 남긴 기억을 한곳에서 봐요.',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(height: 1.65),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SavedTabBar(
                    selectedType: _selectedType,
                    onSelected: (type) => setState(() => _selectedType = type),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                ],
              ),
            ),
            Expanded(
              child: _selectedType == SavedItemType.myRecord
                  ? const FeedScreen(initialFilter: FeedFilter.mine)
                  : const Center(child: Text('저장한 장소 조회는 아직 연결되지 않았어요.')),
            ),
          ],
        ),
      ),
    );
  }
}
