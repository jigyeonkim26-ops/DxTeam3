import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../services/mock_share_card_repository.dart';
import '../widgets/share_card_chip.dart';
import '../widgets/share_card_preview.dart';

class ShareCardScreen extends StatelessWidget {
  const ShareCardScreen({super.key});
  @override
  Widget build(BuildContext c) {
    final data = MockShareCardRepository.card;
    return Scaffold(
      appBar: AppBar(title: const Text('SHARE CARD · 2ND')),
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
            Text(
              '기억을 카드로\n남겨보세요',
              style: Theme.of(c).textTheme.headlineSmall
                  ?.copyWith(fontSize: 27, height: 1.25),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '작성자가 외부 공유를 허용한 기록만 공유 카드로 만들 수 있어요.',
              style: Theme.of(c).textTheme.bodyMedium?.copyWith(height: 1.65),
            ),
            const SizedBox(height: AppSpacing.lg),
            ShareCardPreview(data: data),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '카드 구성',
              style: Theme.of(c).textTheme.titleMedium
                  ?.copyWith(color: AppColors.ink, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                ShareCardChip(label: '사진 ${data.photoCount}장'),
                ShareCardChip(label: data.aspectRatioText),
                ShareCardChip(label: data.themeText),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: () => ScaffoldMessenger.of(c)
                  .showSnackBar(const SnackBar(content: Text('공유 카드를 만들었어요.'))),
              child: const Text('이미지 만들기'),
            ),
            const SizedBox(height: AppSpacing.xs),
            OutlinedButton(
              onPressed: () => ScaffoldMessenger.of(c).showSnackBar(
                const SnackBar(content: Text('공유할 앱을 선택할 수 있는 기능은 추후 연결됩니다.')),
              ),
              child: const Text('다른 앱으로 공유'),
            ),
          ],
        ),
      ),
    );
  }
}
