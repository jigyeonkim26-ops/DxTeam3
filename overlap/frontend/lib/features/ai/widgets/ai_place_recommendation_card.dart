import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/network/api_client.dart' show ApiClient, ApiException;
import '../../../core/network/api_config.dart';
import '../../user/services/saved_places_api.dart';
import '../models/ai_place_recommendation.dart';

class AiPlaceRecommendationCard extends StatefulWidget {
  const AiPlaceRecommendationCard({
    super.key,
    required this.recommendation,
    required this.onTap,
    required this.savedPlacesApi,
  });

  final AiPlaceRecommendation recommendation;
  final VoidCallback? onTap;
  final SavedPlacesApi savedPlacesApi;

  @override
  State<AiPlaceRecommendationCard> createState() =>
      _AiPlaceRecommendationCardState();
}

class _AiPlaceRecommendationCardState extends State<AiPlaceRecommendationCard> {
  bool? _saved;
  int? _placeId;
  bool _loading = true;
  bool _saving = false;
  int _lookupGeneration = 0;

  @override
  void initState() {
    super.initState();
    SavedPlacesApi.revision.addListener(_onSavedPlacesChanged);
    _refresh();
  }

  @override
  void didUpdateWidget(covariant AiPlaceRecommendationCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recommendation.kakaoPlaceId !=
            widget.recommendation.kakaoPlaceId ||
        oldWidget.savedPlacesApi != widget.savedPlacesApi) {
      _saved = null;
      _placeId = null;
      _refresh();
    }
  }

  @override
  void dispose() {
    _lookupGeneration++;
    SavedPlacesApi.revision.removeListener(_onSavedPlacesChanged);
    super.dispose();
  }

  void _onSavedPlacesChanged() {
    if (!_saving) _refresh();
  }

  Future<void> _refresh() async {
    final id = widget.recommendation.kakaoPlaceId;
    final generation = ++_lookupGeneration;
    if (id == null) {
      setState(() {
        _saved = null;
        _loading = false;
      });
      return;
    }
    setState(() => _loading = true);
    try {
      final lookup = await widget.savedPlacesApi.lookupKakao(id);
      if (!mounted || generation != _lookupGeneration) return;
      setState(() {
        _placeId = lookup.placeId;
        _saved = lookup.saved;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _lookupGeneration) return;
      setState(() {
        _saved = null;
        _loading = false;
      });
    }
  }

  Future<void> _toggleSaved() async {
    if (_saving || _loading) return;
    if (_saved == null || (_saved! && _placeId == null)) {
      await _refresh();
      return;
    }
    final recommendation = widget.recommendation;
    final id = recommendation.kakaoPlaceId;
    final address = recommendation.address;
    if (id == null || address == null) return;
    _lookupGeneration++;
    setState(() => _saving = true);
    try {
      final state = _saved!
          ? await widget.savedPlacesApi.unsave(_placeId!)
          : _placeId != null
          ? await widget.savedPlacesApi.save(_placeId!)
          : await widget.savedPlacesApi.saveKakao(
              id,
              name: recommendation.name,
              address: address,
            );
      if (!mounted) return;
      setState(() {
        _saved = state.saved;
        _placeId = state.placeId;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
      await _refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('즐겨찾기 상태를 변경하지 못했어요.')));
      await _refresh();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recommendation = widget.recommendation;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '나와 잘 맞는 장소',
                style: TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RecommendationThumbnail(recommendation: recommendation),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                recommendation.name,
                                softWrap: true,
                                style: const TextStyle(
                                  color: AppColors.deepNavy,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {},
                              child: IconButton(
                                visualDensity: VisualDensity.compact,
                                iconSize: 20,
                                onPressed:
                                    recommendation.kakaoPlaceId == null ||
                                        recommendation.address == null ||
                                        _loading ||
                                        _saving
                                    ? null
                                    : _toggleSaved,
                                tooltip: _saved == null
                                    ? '즐겨찾기 상태 다시 확인'
                                    : _saved!
                                    ? '즐겨찾기 해제'
                                    : '즐겨찾기',
                                icon: _loading || _saving
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Icon(
                                        _saved == null
                                            ? Icons.sync_problem_outlined
                                            : _saved!
                                            ? Icons.bookmark
                                            : Icons.bookmark_border,
                                        color: _saved == true
                                            ? AppColors.coral
                                            : AppColors.deepNavy,
                                      ),
                              ),
                            ),
                          ],
                        ),
                        if (recommendation.address != null) ...[
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            recommendation.address!,
                            softWrap: true,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                        if (recommendation.matchedKeywords.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.sm),
                          Wrap(
                            spacing: AppSpacing.xxs,
                            runSpacing: AppSpacing.xxs,
                            children: [
                              for (final keyword
                                  in recommendation.matchedKeywords)
                                _KeywordChip(label: keyword),
                            ],
                          ),
                        ],
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          recommendation.reason,
                          softWrap: true,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecommendationThumbnail extends StatefulWidget {
  const _RecommendationThumbnail({required this.recommendation});

  final AiPlaceRecommendation recommendation;

  @override
  State<_RecommendationThumbnail> createState() =>
      _RecommendationThumbnailState();
}

class _RecommendationThumbnailState extends State<_RecommendationThumbnail> {
  bool _successLogged = false;
  bool _missingLogged = false;

  @override
  void didUpdateWidget(covariant _RecommendationThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.recommendation.imageUrl != widget.recommendation.imageUrl) {
      _successLogged = false;
      _missingLogged = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final recommendation = widget.recommendation;
    final imageUrl = recommendation.imageUrl;
    if (imageUrl == null || imageUrl.isEmpty) {
      if (kDebugMode && !_missingLogged) {
        _missingLogged = true;
        debugPrint(
          '[AI_IMAGE] url_missing origin=${recommendation.imageOriginType} '
          'source=${recommendation.imageSource ?? 'unknown'}',
        );
      }
      return _thumbnail(_PlaceholderThumbnail(recommendation: recommendation));
    }

    final isRelative = imageUrl.startsWith('/');
    final url = isRelative ? '${ApiConfig.baseUrl}$imageUrl' : imageUrl;
    final image = Image.network(
      url,
      width: 84,
      height: 84,
      cacheWidth: 240,
      cacheHeight: 240,
      fit: BoxFit.cover,
      headers: isRelative
          ? {'Authorization': 'Bearer ${ApiClient.accessToken ?? ''}'}
          : null,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame != null && !_successLogged) {
          _successLogged = true;
          if (kDebugMode) {
            debugPrint(
              '[AI_IMAGE] loaded origin=${recommendation.imageOriginType}',
            );
          }
        }
        return frame != null || wasSynchronouslyLoaded
            ? child
            : _PlaceholderThumbnail(recommendation: recommendation);
      },
      errorBuilder: (context, error, stackTrace) {
        if (kDebugMode) {
          final type = error.runtimeType.toString();
          final detail = error is NetworkImageLoadException
              ? 'http status=${error.statusCode}'
              : type.toLowerCase().contains('codec')
              ? 'decode error_type=$type'
              : 'load error_type=$type';
          debugPrint(
            '[AI_IMAGE] failed origin=${recommendation.imageOriginType} $detail',
          );
        }
        return _PlaceholderThumbnail(recommendation: recommendation);
      },
    );
    return _thumbnail(image);
  }

  Widget _thumbnail(Widget image) => ClipRRect(
    borderRadius: BorderRadius.circular(AppSpacing.sm),
    child: SizedBox(width: 84, height: 84, child: image),
  );
}

class _PlaceholderThumbnail extends StatelessWidget {
  const _PlaceholderThumbnail({required this.recommendation});

  final AiPlaceRecommendation recommendation;

  @override
  Widget build(BuildContext context) {
    final keywords = recommendation.matchedKeywords.join(' ');
    final icon = keywords.contains('카페')
        ? Icons.local_cafe_outlined
        : keywords.contains('전시') || keywords.contains('문화')
        ? Icons.museum_outlined
        : keywords.contains('산책') || keywords.contains('자연')
        ? Icons.park_outlined
        : keywords.contains('음식') || keywords.contains('맛집')
        ? Icons.restaurant_outlined
        : Icons.place_outlined;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.paleMint,
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Center(child: Icon(icon, color: AppColors.deepNavy, size: 30)),
    );
  }
}

class _KeywordChip extends StatelessWidget {
  const _KeywordChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: AppColors.paleMint,
        borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppColors.deepNavy,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
