import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/place.dart';
import '../widgets/place_search_result_tile.dart';

class PlaceSearchScreen extends StatefulWidget {
  const PlaceSearchScreen({super.key});

  @override
  State<PlaceSearchScreen> createState() => _PlaceSearchScreenState();
}

class _PlaceSearchScreenState extends State<PlaceSearchScreen> {
  final _searchController = TextEditingController();

  static const List<Place> _places = [
    Place(
      id: 'search-yeonnam-cafe',
      name: '연남동 작은 카페',
      latitude: 37.5665,
      longitude: 126.9250,
      address: '서울 마포구 연남동',
      recordCount: 4,
    ),
    Place(
      id: 'search-seongsu-cafe-street',
      name: '성수 카페거리',
      latitude: 37.5446,
      longitude: 127.0559,
      address: '서울 성동구 성수동',
    ),
    Place(
      id: 'search-seoul-forest',
      name: '서울숲',
      latitude: 37.5444,
      longitude: 127.0374,
      address: '서울 성동구 성수동',
    ),
    Place(
      id: 'search-hangang-park',
      name: '한강공원',
      latitude: 37.5287,
      longitude: 126.9325,
      address: '서울 영등포구 여의도동',
    ),
    Place(
      id: 'search-bukchon',
      name: '북촌한옥마을',
      latitude: 37.5826,
      longitude: 126.9830,
      address: '서울 종로구 북촌',
    ),
    Place(
      id: 'search-gwangalli',
      name: '광안리해수욕장',
      latitude: 35.1532,
      longitude: 129.1186,
      address: '부산 수영구 광안동',
    ),
    Place(
      id: 'search-dongjin-market',
      name: '동진시장',
      latitude: 37.5625,
      longitude: 126.9237,
      address: '서울 마포구 연남동',
      recordCount: 2,
    ),
  ];

  String get _query => _searchController.text;

  List<Place> get _results {
    final normalizedQuery = _normalize(_query);
    if (normalizedQuery.isEmpty) return const [];
    return _places
        .where(
          (place) =>
              _normalize(place.name).contains(normalizedQuery) ||
              _normalize(place.address ?? '').contains(normalizedQuery),
        )
        .toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  void _clearQuery() => _searchController.clear();

  @override
  Widget build(BuildContext context) {
    final hasQuery = _query.trim().isNotEmpty;
    final results = _results;
    final recentPlaces = _places.take(2).toList();
    return Scaffold(
      backgroundColor: AppColors.paper,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
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
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: '장소 또는 주소 검색',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: hasQuery
                            ? IconButton(
                                onPressed: _clearQuery,
                                icon: const Icon(Icons.close_rounded),
                                tooltip: '검색어 지우기',
                              )
                            : null,
                        filled: true,
                        fillColor: AppColors.surface,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.xs,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppSpacing.buttonRadius,
                          ),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.lg,
                ),
                children: [
                  Text(
                    hasQuery ? '검색 결과' : '어디를 찾고 있나요?',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: AppColors.deepNavy,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    hasQuery
                        ? '장소명 또는 주소와 일치하는 장소예요.'
                        : '찾고 싶은 장소나 주소를 검색해보세요.',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (!hasQuery) ...[
                    const Text(
                      '최근 찾은 장소',
                      style: TextStyle(
                        color: AppColors.deepNavy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    for (final place in recentPlaces) ...[
                      PlaceSearchResultTile(
                        place: place,
                        onTap: () => Navigator.pop(context, place),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ] else if (results.isEmpty) ...[
                    const SizedBox(height: AppSpacing.xl),
                    const _SearchEmptyState(),
                  ] else
                    for (final place in results) ...[
                      PlaceSearchResultTile(
                        place: place,
                        onTap: () => Navigator.pop(context, place),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchEmptyState extends StatelessWidget {
  const _SearchEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        children: [
          Icon(Icons.search_off_outlined, color: AppColors.muted, size: 40),
          SizedBox(height: AppSpacing.sm),
          Text(
            '검색 결과가 없어요.',
            style: TextStyle(
              color: AppColors.deepNavy,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: AppSpacing.xxs),
          Text(
            '다른 장소명이나 주소로 검색해보세요.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}
