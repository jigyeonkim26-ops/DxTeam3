import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/place.dart';
import '../data/mock_ai_recommendations.dart';
import '../widgets/ai_place_recommendation_card.dart';

class AiRecommendationScreen extends StatelessWidget {
  const AiRecommendationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: AiRecommendationContent(
          showNavigation: true,
          onPlaceSelected: (place) => Navigator.pop(context, place),
        ),
      ),
    );
  }
}

class AiRecommendationContent extends StatefulWidget {
  const AiRecommendationContent({
    super.key,
    this.scrollController,
    this.showNavigation = false,
    this.showSheetHeader = false,
    this.onPlaceSelected,
  });

  final ScrollController? scrollController;
  final bool showNavigation;
  final bool showSheetHeader;
  final ValueChanged<Place>? onPlaceSelected;

  @override
  State<AiRecommendationContent> createState() =>
      _AiRecommendationContentState();
}

class _AiRecommendationContentState extends State<AiRecommendationContent> {
  final List<AiPlaceRecommendation> _recommendations = const [];

  @override
  Widget build(BuildContext context) {
    final content = ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      children: [
        if (widget.showSheetHeader) ...[
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: Container(
              width: 42,
              height: 5,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Text(
              'AI 장소 추천',
              style: TextStyle(
                color: AppColors.deepNavy,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
        if (widget.showNavigation)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back),
                  color: AppColors.deepNavy,
                  tooltip: '뒤로가기',
                ),
                const SizedBox(width: AppSpacing.xxs),
                const Expanded(
                  child: Text(
                    'AI 장소 추천',
                    style: TextStyle(
                      color: AppColors.deepNavy,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
              ],
            ),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
            0,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'FOR YOU',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '새롭게 발견할 장소',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: AppColors.deepNavy,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.paleMint,
                  borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
                ),
                child: Text(
                  '${_recommendations.length}곳',
                  style: const TextStyle(
                    color: AppColors.deepNavy,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Text('아직 추천 장소가 없어요.', textAlign: TextAlign.center),
        ),
        for (final recommendation in _recommendations) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: AiPlaceRecommendationCard(
              recommendation: recommendation,
              onTap: () {
                final onPlaceSelected = widget.onPlaceSelected;
                if (onPlaceSelected != null) {
                  onPlaceSelected(recommendation.place);
                } else {
                  Navigator.maybePop(context);
                }
              },
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
    if (!widget.showSheetHeader) return content;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.16),
            blurRadius: 16,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: content,
    );
  }
}
