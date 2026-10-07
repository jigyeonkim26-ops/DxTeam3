import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/models/emotion.dart';
import '../../../shared/models/place.dart';
import '../models/ai_place_recommendation.dart';
import '../widgets/ai_place_recommendation_card.dart';

class AiRecommendationScreen extends StatefulWidget {
  const AiRecommendationScreen({super.key});

  @override
  State<AiRecommendationScreen> createState() => _AiRecommendationScreenState();
}

class _AiRecommendationScreenState extends State<AiRecommendationScreen> {
  List<AiPlaceRecommendation> _recommendations = const [];
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadRecommendations();
  }

  Future<void> _loadRecommendations() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final response = await ApiClient.getAiRecommendations();
      if (!mounted) return;
      setState(() {
        _recommendations = response.recommendations;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = '\uCD94\uCC9C \uC815\uBCF4\uB97C \uBD88\uB7EC\uC624\uC9C0 \uBABB\uD588\uC5B4\uC694.';
      });
    }
  }

  void _openRecommendation(AiPlaceRecommendation recommendation) {
    final latitude = recommendation.latitude;
    final longitude = recommendation.longitude;
    if (latitude == null || longitude == null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('\uC774 \uCD94\uCC9C \uC7A5\uC18C\uB294 \uC9C0\uB3C4 \uC88C\uD45C\uAC00 \uC544\uC9C1 \uC5C6\uC5B4\uC694.'),
          ),
        );
      return;
    }
    Navigator.pop(
      context,
      Place(
        id: 'ai-recommendation-${recommendation.rank}',
        name: recommendation.name,
        latitude: latitude,
        longitude: longitude,
        address: recommendation.address,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
          children: [
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
                onPressed: _isLoading ? null : _loadRecommendations,
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
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_loadError != null)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: _RecommendationMessage(
                  message: _loadError!,
                  actionLabel: '\uB2E4\uC2DC \uC2DC\uB3C4',
                  onAction: _loadRecommendations,
                ),
              )
            else if (_recommendations.isEmpty)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: _RecommendationMessage(
                  message: '\uC544\uC9C1 \uCD94\uCC9C\uD560 \uC7A5\uC18C\uAC00 \uC5C6\uC5B4\uC694.\n\uC88B\uC558\uB358 \uC7A5\uC18C\uC758 \uAE30\uB85D\uC744 \uB0A8\uAE30\uBA74 \uCDE8\uD5A5\uC5D0 \uB9DE\uB294 \uC7A5\uC18C\uB97C \uCD94\uCC9C\uD574\uB4DC\uB9B4\uAC8C\uC694.',
                ),
              )
            else
              for (final recommendation in _recommendations) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: AiPlaceRecommendationCard(
                    recommendation: recommendation,
                    onTap: () => _openRecommendation(recommendation),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
          ],
        ),
      ),
    );
  }
}

class _RecommendationMessage extends StatelessWidget {
  const _RecommendationMessage({
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        border: Border.all(color: AppColors.softMint),
      ),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.muted, height: 1.5),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(actionLabel!),
            ),
          ],
        ],
      ),
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
