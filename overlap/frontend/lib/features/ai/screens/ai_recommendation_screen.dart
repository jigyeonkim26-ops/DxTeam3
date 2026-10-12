import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/network/api_client.dart' show ApiException;
import '../../../shared/models/place.dart';
import '../models/ai_place_recommendation.dart';
import '../services/ai_recommendations_api.dart';
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
  final _api = AiRecommendationsApi();
  List<AiPlaceRecommendation> _recommendations = const [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _api.load();
      if (mounted) setState(() => _recommendations = items);
    } on ApiException catch (e) {
      if (mounted)
        setState(
          () => _error = e.statusCode == 401
              ? '로그인이 필요해요.'
              : e.statusCode == 502
              ? 'AI 추천 서비스에 일시적인 문제가 있어요.'
              : e.message,
        );
    } catch (_) {
      if (mounted) setState(() => _error = '추천 장소를 불러오지 못했어요.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                Text(_error!, textAlign: TextAlign.center),
                TextButton(onPressed: _load, child: const Text('다시 추천받기')),
              ],
            ),
          )
        else if (_recommendations.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                const Text('아직 추천 장소가 없어요.', textAlign: TextAlign.center),
                TextButton(
                  onPressed: _loading ? null : _load,
                  child: const Text('다시 추천받기'),
                ),
              ],
            ),
          )
        else
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _loading ? null : _load,
              child: const Text('다른 장소 추천받기'),
            ),
          ),
        for (final recommendation in _recommendations) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: AiPlaceRecommendationCard(
              recommendation: recommendation,
              onTap: () {
                final onPlaceSelected = widget.onPlaceSelected;
                if (onPlaceSelected != null &&
                    recommendation.latitude != null &&
                    recommendation.longitude != null) {
                  onPlaceSelected(
                    Place(
                      id: recommendation.sourceUrl,
                      name: recommendation.name,
                      address: recommendation.address,
                      latitude: recommendation.latitude!,
                      longitude: recommendation.longitude!,
                    ),
                  );
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
