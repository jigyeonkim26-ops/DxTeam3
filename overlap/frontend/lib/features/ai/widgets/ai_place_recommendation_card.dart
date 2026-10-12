import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/network/api_client.dart' show ApiException;
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
  State<AiPlaceRecommendationCard> createState() => _AiPlaceRecommendationCardState();
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
    if (oldWidget.recommendation.kakaoPlaceId != widget.recommendation.kakaoPlaceId ||
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
                  id, name: recommendation.name, address: address,
                );
      if (!mounted) return;
      setState(() {
        _saved = state.saved;
        _placeId = state.placeId;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
      await _refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('즐겨찾기 상태를 변경하지 못했어요.')),
      );
      await _refresh();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Text(
                        widget.recommendation.name,
                        softWrap: true,
                        style: const TextStyle(
                          color: AppColors.deepNavy,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: IconButton(
                      visualDensity: VisualDensity.compact,
                      iconSize: 20,
                      onPressed: widget.recommendation.kakaoPlaceId == null ||
                              widget.recommendation.address == null || _loading || _saving
                          ? null : _toggleSaved,
                      tooltip: _saved == null ? '즐겨찾기 상태 다시 확인' :
                          _saved! ? '즐겨찾기 해제' : '즐겨찾기',
                      icon: _loading || _saving
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _saved == null ? Icons.sync_problem_outlined :
                                  _saved! ? Icons.bookmark : Icons.bookmark_border,
                              color: _saved == true ? AppColors.coral : AppColors.deepNavy,
                            ),
                    ),
                  ),
                ],
              ),
              if (widget.recommendation.address != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  widget.recommendation.address!,
                  softWrap: true,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
              ],
              if (widget.recommendation.matchedKeywords.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.xxs,
                  runSpacing: AppSpacing.xxs,
                  children: [
                    for (final keyword in widget.recommendation.matchedKeywords)
                      _KeywordChip(label: keyword),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Text(
                widget.recommendation.reason,
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
      ),
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
