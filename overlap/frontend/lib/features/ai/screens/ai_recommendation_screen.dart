import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/emotion.dart';
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
  int _recommendationSetIndex = 0;

  List<AiPlaceRecommendation> get _recommendations =>
      mockAiRecommendationSets[_recommendationSetIndex];

  void _refreshRecommendations() {
    setState(() {
      _recommendationSetIndex =
          (_recommendationSetIndex + 1) % mockAiRecommendationSets.length;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('새로운 추천을 가져왔어요.')));
  }

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
            const _AnalysisHero(),
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
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
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
                      borderRadius: BorderRadius.circular(
                        AppSpacing.pillRadius,
                      ),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: OutlinedButton.icon(
                onPressed: _refreshRecommendations,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('다른 장소 추천받기'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.deepNavy,
                  side: const BorderSide(color: AppColors.softMint),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
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

class _AnalysisHero extends StatelessWidget {
  const _AnalysisHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.paleMint, AppColors.paper],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.softMint),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AI RECOMMENDATION · 목업',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text(
            '최근 기록을\n분석했어요',
            style: TextStyle(
              color: AppColors.deepNavy,
              fontSize: 25,
              height: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            '좋아했던 순간에서 이런 특징이 많이 나타났어요.',
            style: TextStyle(color: AppColors.muted, height: 1.5),
          ),
          const SizedBox(height: AppSpacing.md),
          const Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              _InsightChip(label: '노을'),
              _InsightChip(label: '산책'),
              _InsightChip(label: '조용한 공간'),
              _InsightChip(label: '카페'),
              _InsightChip(label: '친구와 함께'),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const _EmotionSummary(),
          const SizedBox(height: AppSpacing.sm),
          const Text(
            '산책과 카페에서 남긴 기록의 만족도가 높았어요. 노을, 조용함, 친구와 함께한 장소를 긍정적으로 기억하고 있어요.',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

class _InsightChip extends StatelessWidget {
  const _InsightChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.deepNavy,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmotionSummary extends StatelessWidget {
  const _EmotionSummary();

  @override
  Widget build(BuildContext context) {
    const insights = [
      (emotion: Emotion.good, count: 3),
      (emotion: Emotion.excellent, count: 2),
      (emotion: Emotion.okay, count: 1),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.softMint),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '최근 긍정적으로 기억한 경험',
            style: TextStyle(
              color: AppColors.deepNavy,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              for (final insight in insights)
                Text(
                  '${insight.emotion.emoji} ${insight.emotion.displayName} ${insight.count}회',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
