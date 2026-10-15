import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/network/api_client.dart' show ApiException;
import '../../../shared/models/place.dart';
import '../../user/services/saved_places_api.dart';
import '../models/ai_place_recommendation.dart';
import '../services/ai_recommendations_api.dart';
import '../widgets/ai_place_recommendation_card.dart';

class AiRecommendationScreen extends StatelessWidget {
  const AiRecommendationScreen({super.key, this.api, this.savedPlacesApi});

  final AiRecommendationsApi? api;
  final SavedPlacesApi? savedPlacesApi;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      body: SafeArea(
        child: AiRecommendationContent(
          api: api,
          savedPlacesApi: savedPlacesApi,
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
    this.onRecommendationSelected,
    this.api,
    this.savedPlacesApi,
  });

  final ScrollController? scrollController;
  final bool showNavigation;
  final bool showSheetHeader;
  final ValueChanged<Place>? onPlaceSelected;
  final ValueChanged<AiPlaceRecommendation>? onRecommendationSelected;
  final AiRecommendationsApi? api;
  final SavedPlacesApi? savedPlacesApi;

  @override
  State<AiRecommendationContent> createState() =>
      _AiRecommendationContentState();
}

class _AiRecommendationContentState extends State<AiRecommendationContent> {
  late final _api = widget.api ?? AiRecommendationsApi();
  late final _savedPlacesApi = widget.savedPlacesApi ?? SavedPlacesApi();
  List<AiPlaceRecommendation> _recommendations = const [];
  int _recommendationsRevision = 0;
  bool _loading = false;
  bool _sessionExhausted = false;
  String? _error;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadRecommendations();
  }

  Future<void> _loadRecommendations() async {
    if (_loading) return;
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    await _requestRecommendations(generation);
  }

  Future<void> _requestRecommendations(int generation) async {
    final stopwatch = Stopwatch()..start();
    try {
      final items = await _api.load();
      if (!mounted) return;
      if (generation != _requestGeneration) {
        if (kDebugMode) {
          debugPrint(
            '[AI recommendations UI] stale_response_ignored=1 elapsed_ms=${stopwatch.elapsedMilliseconds}',
          );
        }
        return;
      }
      setState(() {
        _sessionExhausted = _api.sessionStatus == 'exhausted';
        // Exhaustion is a normal session outcome. Keep the last visible cards
        // and signal that no unseen candidates remain instead of replacing
        // them with an empty list.
        if (!_sessionExhausted || items.isNotEmpty) {
          _recommendations = items;
          _recommendationsRevision++;
        }
      });
    } on ApiException catch (e) {
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(
        () => _error = e.statusCode == 401
            ? '로그인이 만료되었어요. 다시 로그인해 주세요.'
            : e.kind.name == 'timeout'
            ? '추천 요청 시간이 초과됐어요. 다시 시도해 주세요.'
            : e.kind.name == 'network'
            ? '네트워크 연결을 확인하고 다시 시도해 주세요.'
            : (e.statusCode ?? 0) >= 500
            ? '추천 서버에 일시적인 문제가 있어요. 잠시 후 다시 시도해 주세요.'
            : e.message,
      );
    } catch (_) {
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() => _error = '추천 장소를 불러오지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loading = false);
      }
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
                TextButton(
                  onPressed: () => _loadRecommendations(),
                  child: const Text('다시 추천받기'),
                ),
              ],
            ),
          )
        else if (_recommendations.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              children: [
                const Text(
                  '\uCDE8\uD5A5\uC5D0 \uB9DE\uB294 \uC7A5\uC18C\uB97C \uC544\uC9C1 \uCC3E\uC9C0 \uBABB\uD588\uC5B4\uC694.',
                  textAlign: TextAlign.center,
                ),
                TextButton(
                  onPressed: _loading ? null : () => _loadRecommendations(),
                  child: const Text('\uB2E4\uC2DC \uCD94\uCC9C\uBC1B\uAE30'),
                ),
              ],
            ),
          )
        else if (_sessionExhausted)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text(
              '\uC9C0\uAE08\uC740 \uC0C8\uB85C\uC6B4 \uCD94\uCC9C \uC7A5\uC18C\uAC00 \uB354 \uC5C6\uC5B4\uC694.',
              textAlign: TextAlign.center,
            ),
          )
        else
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _loading ? null : () => _loadRecommendations(),
              child: const Text(
                '\uB2E4\uC74C \uC7A5\uC18C \uCD94\uCC9C\uBC1B\uAE30',
              ),
            ),
          ),
        for (final recommendation in _recommendations) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: AiPlaceRecommendationCard(
              key: ValueKey((
                recommendation.kakaoPlaceId ?? recommendation.name,
                _recommendationsRevision,
              )),
              recommendation: recommendation,
              savedPlacesApi: _savedPlacesApi,
              onTap: () {
                if (widget.onRecommendationSelected != null &&
                    recommendation.kakaoPlaceId != null &&
                    recommendation.latitude != null &&
                    recommendation.longitude != null) {
                  widget.onRecommendationSelected!(recommendation);
                  return;
                }
                final onPlaceSelected = widget.onPlaceSelected;
                if (onPlaceSelected != null &&
                    recommendation.kakaoPlaceId != null &&
                    recommendation.latitude != null &&
                    recommendation.longitude != null) {
                  onPlaceSelected(
                    Place(
                      id: recommendation.kakaoPlaceId!,
                      name: recommendation.name,
                      address: recommendation.address,
                      latitude: recommendation.latitude!,
                      longitude: recommendation.longitude!,
                    ),
                  );
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
