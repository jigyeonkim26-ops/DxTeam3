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

const _recommendationCategories = <({String label, String value})>[
  (label: '\u{c804}\u{ccb4}', value: 'all'),
  (label: '\u{b9db}\u{c9d1}', value: 'food'),
  (label: '\u{c220}\u{c9d1}', value: 'bar'),
  (label: '\u{ce74}\u{d398}', value: 'cafe'),
  (label: '\u{c790}\u{c5f0}\u{c0b0}\u{cc45}', value: 'nature'),
  (label: '\u{bb38}\u{d654}\u{c2a4}\u{d3ec}\u{ce20}', value: 'activity'),
];

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
  String? _error;
  String _category = 'all';
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadCategory(_category);
  }

  Future<void> _selectCategory(String category) async {
    if (category == _category) return;
    final generation = ++_requestGeneration;
    setState(() {
      _category = category;
      _recommendations = const [];
      _error = null;
      _loading = true;
    });
    await _requestCategory(category, generation);
  }

  Future<void> _loadCategory(String category) async {
    if (_loading) return;
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    await _requestCategory(category, generation);
  }

  Future<void> _requestCategory(String category, int generation) async {
    final stopwatch = Stopwatch()..start();
    try {
      final items = await _api.load(category: category);
      if (!mounted) return;
      if (generation != _requestGeneration || category != _category) {
        if (kDebugMode) {
          debugPrint(
            '[AI recommendations UI] category=$category stale_response_ignored=1 elapsed_ms=${stopwatch.elapsedMilliseconds}',
          );
        }
        return;
      }
      setState(() {
        _recommendations = items;
        _recommendationsRevision++;
      });
    } on ApiException catch (e) {
      if (!mounted ||
          generation != _requestGeneration ||
          category != _category) {
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
      if (!mounted ||
          generation != _requestGeneration ||
          category != _category) {
        return;
      }
      setState(() => _error = '추천 장소를 불러오지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted &&
          generation == _requestGeneration &&
          category == _category) {
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
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              primary: false,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              itemCount: _recommendationCategories.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
              itemBuilder: (context, index) {
                final item = _recommendationCategories[index];
                final selected = item.value == _category;
                return ChoiceChip(
                  label: Text(item.label, maxLines: 1, softWrap: false),
                  selected: selected,
                  onSelected: (_) => _selectCategory(item.value),
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                  ),
                  labelStyle: TextStyle(
                    color: selected ? AppColors.surface : AppColors.deepNavy,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  backgroundColor: AppColors.paleMint,
                  selectedColor: AppColors.deepNavy,
                  side: BorderSide(
                    color: selected ? AppColors.deepNavy : AppColors.divider,
                  ),
                );
              },
            ),
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
                  onPressed: () => _loadCategory(_category),
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
                  '\u{c774}\u{20}\u{bd84}\u{c57c}\u{c5d0}\u{c11c}\u{20}\u{cde8}\u{d5a5}\u{c5d0}\u{20}\u{b9de}\u{b294}\u{20}\u{c7a5}\u{c18c}\u{b97c}\u{20}\u{c544}\u{c9c1}\u{20}\u{cc3e}\u{c9c0}\u{20}\u{babb}\u{d588}\u{c5b4}\u{c694}\u{2e}',
                  textAlign: TextAlign.center,
                ),
                TextButton(
                  onPressed: _loading ? null : () => _loadCategory(_category),
                  child: const Text('\uB2E4\uC2DC \uCD94\uCC9C\uBC1B\uAE30'),
                ),
              ],
            ),
          )
        else
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _loading ? null : () => _loadCategory(_category),
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
