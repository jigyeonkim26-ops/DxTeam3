import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/emotion.dart';

String _displayLabel(Emotion emotion) {
  switch (emotion) {
    case Emotion.excellent:
      return '최고예요';
    case Emotion.good:
      return '좋아요';
    case Emotion.okay:
      return '괜찮아요';
    case Emotion.neutral:
      return '그저 그래요';
    case Emotion.disappointed:
      return '아쉬워요';
    case Emotion.poor:
      return '별로예요';
  }
}

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
    return SizedBox(
      height: 76,
      child: Row(
        children: [
          for (final emotion in Emotion.values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                child: _EmotionChoice(
                  emotion: emotion,
                  isSelected: selectedEmotion == emotion,
                  onTap: () => onSelected(emotion),
                ),
              ),
            ),
        ],
      ),
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
            Text(emotion.emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: AppSpacing.xxs),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _displayLabel(emotion),
                maxLines: 1,
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
