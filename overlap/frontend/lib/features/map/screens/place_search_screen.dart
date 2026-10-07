import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/place.dart';
import '../models/kakao_place_search_result.dart';
import '../services/place_search_api.dart';
import '../widgets/place_search_result_tile.dart';

class PlaceSearchScreen extends StatefulWidget {
  const PlaceSearchScreen({super.key});

  @override
  State<PlaceSearchScreen> createState() => _PlaceSearchScreenState();
}

class _PlaceSearchScreenState extends State<PlaceSearchScreen> {
  final _searchController = TextEditingController();
  final _searchApi = PlaceSearchApi();
  Timer? _debounce;
  List<KakaoPlaceSearchResult> _results = const [];
  PlaceSearchException? _error;
  var _isLoading = false;
  var _hasCompletedSearch = false;
  var _requestGeneration = 0;

  String get _query => _searchController.text.trim();

  @override
  void dispose() {
    _debounce?.cancel();
    _requestGeneration++;
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String _) {
    _debounce?.cancel();
    final generation = ++_requestGeneration;
    final query = _query;
    setState(() {
      _results = const [];
      _error = null;
      _isLoading = false;
      _hasCompletedSearch = false;
    });
    if (query.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _runSearch(query, generation);
    });
  }

  Future<void> _retrySearch() {
    _debounce?.cancel();
    final generation = ++_requestGeneration;
    return _runSearch(_query, generation);
  }

  Future<void> _runSearch(String query, int generation) async {
    if (query.isEmpty || !mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
      _results = const [];
      _hasCompletedSearch = false;
    });
    try {
      final results = await _searchApi.search(query);
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _results = results;
        _isLoading = false;
        _hasCompletedSearch = true;
      });
    } on PlaceSearchException catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _error = error;
        _isLoading = false;
        _hasCompletedSearch = true;
      });
    } catch (_) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _error = const PlaceSearchException(
          PlaceSearchErrorKind.invalidResponse,
          '장소 검색 응답을 처리하지 못했습니다.',
        );
        _isLoading = false;
        _hasCompletedSearch = true;
      });
    }
  }

  void _clearQuery() {
    _searchController.clear();
    _onQueryChanged('');
  }

  Place _toPlace(KakaoPlaceSearchResult result) => Place(
    id: result.kakaoPlaceId,
    name: result.name,
    latitude: result.latitude,
    longitude: result.longitude,
    address: result.address,
  );

  @override
  Widget build(BuildContext context) {
    final hasQuery = _query.isNotEmpty;
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
                      onChanged: _onQueryChanged,
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
                    hasQuery ? '장소명 또는 주소 검색 결과예요.' : '찾고 싶은 장소나 주소를 검색해보세요.',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null)
                    _SearchErrorState(
                      message: _error!.message,
                      onRetry: _retrySearch,
                    )
                  else if (hasQuery && _hasCompletedSearch && _results.isEmpty)
                    const _SearchEmptyState()
                  else if (hasQuery)
                    const Text(
                      '검색 결과를 불러올 준비 중이에요.',
                      style: TextStyle(color: AppColors.muted),
                    )
                  else if (!hasQuery)
                    const Text(
                      '검색어를 입력하면 장소 검색 결과를 보여드려요.',
                      style: TextStyle(color: AppColors.muted),
                    )
                  else
                    for (final result in _results) ...[
                      PlaceSearchResultTile(
                        place: _toPlace(result),
                        onTap: () => Navigator.pop(context, _toPlace(result)),
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
  Widget build(BuildContext context) => const Center(
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

class _SearchErrorState extends StatelessWidget {
  const _SearchErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      children: [
        const Icon(Icons.wifi_off_rounded, color: AppColors.muted, size: 40),
        const SizedBox(height: AppSpacing.sm),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.sm),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('다시 시도'),
        ),
      ],
    ),
  );
}
