import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/emotion.dart';

class EmotionPicker extends StatelessWidget {
  const EmotionPicker({
    super.key,
    required this.selectedEmotion,
    required this.onSelected,
  });

  final Emotion? selectedEmotion;
  final ValueChanged<Emotion> onSelected;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.xs,
      crossAxisSpacing: AppSpacing.xs,
      childAspectRatio: 1.15,
      children: [
        for (final emotion in Emotion.values)
          _EmotionChoice(
            emotion: emotion,
            isSelected: selectedEmotion == emotion,
            onTap: () => onSelected(emotion),
          ),
      ],
    );
  }
}

class _EmotionChoice extends StatelessWidget {
  const _EmotionChoice({
    required this.emotion,
    required this.isSelected,
    required this.onTap,
  });

  final Emotion emotion;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = isSelected ? AppColors.paleMint : AppColors.surface;
    final border = isSelected ? AppColors.deepNavy : AppColors.divider;
    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: border, width: isSelected ? 1.5 : 1),
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emotion.emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              emotion.displayName,
              style: TextStyle(
                color: AppColors.ink,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
