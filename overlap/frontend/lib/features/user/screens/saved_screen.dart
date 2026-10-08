import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/network/api_client.dart';
import '../models/saved_place.dart';
import '../services/saved_places_api.dart';

class SavedScreen extends StatefulWidget {
  const SavedScreen({
    super.key,
    this.savedPlacesApi,
    this.embedded = false,
    this.isActive = true,
  });

  final SavedPlacesApi? savedPlacesApi;
  final bool embedded;
  final bool isActive;

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  late final SavedPlacesApi _savedPlacesApi;
  List<SavedPlace> _places = const [];
  bool _isLoading = true;
  String? _errorMessage;
  int _loadGeneration = 0;
  final Set<int> _removingPlaceIds = {};

  @override
  void initState() {
    super.initState();
    _savedPlacesApi = widget.savedPlacesApi ?? SavedPlacesApi();
    SavedPlacesApi.revision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _loadGeneration++;
    SavedPlacesApi.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final places = await _savedPlacesApi.list();
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _places = places;
        _isLoading = false;
      });
    } on ApiException catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _isLoading = false;
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _isLoading = false;
        _errorMessage = '저장한 장소를 불러오지 못했어요.';
      });
    }
  }

  @override
  void didUpdateWidget(covariant SavedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) _load();
  }

  Future<void> _removeSavedPlace(SavedPlace place) async {
    if (!_removingPlaceIds.add(place.placeId)) return;
    setState(() {});
    try {
      await _savedPlacesApi.unsave(place.placeId);
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('저장을 취소하지 못했어요. 다시 시도해 주세요.')),
          );
      }
    } finally {
      _removingPlaceIds.remove(place.placeId);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [_buildIntro(), _buildBody()],
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('저장한 장소')),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildIntro(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildIntro() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '가보고 싶은 곳',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontSize: 27,
              height: 1.25,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '가보고 싶은 장소를 저장해두고 나중에 다시 찾아보세요.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              height: 1.65,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_errorMessage!),
            TextButton(onPressed: _load, child: const Text('다시 시도')),
          ],
        ),
      );
    }
    if (_places.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('저장한 장소가 없어요.'),
            SizedBox(height: AppSpacing.xs),
            Text('가보고 싶은 장소를 저장해보세요.'),
          ],
        ),
      );
    }
    return ListView.separated(
      shrinkWrap: widget.embedded,
      physics: widget.embedded ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      itemCount: _places.length,
      separatorBuilder: (_, _) => const Divider(color: AppColors.divider),
      itemBuilder: (_, index) => _SavedPlaceRow(
        place: _places[index],
        isRemoving: _removingPlaceIds.contains(_places[index].placeId),
        onRemove: () => _removeSavedPlace(_places[index]),
      ),
    );
  }
}

class _SavedPlaceRow extends StatelessWidget {
  const _SavedPlaceRow({
    required this.place,
    required this.isRemoving,
    required this.onRemove,
  });

  final SavedPlace place;
  final bool isRemoving;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.softMint,
              borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
            ),
            child: const Icon(
              Icons.bookmark,
              color: AppColors.deepNavy,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  place.name,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (place.displayAddress case final address?) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    address,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: '저장 취소',
            onPressed: isRemoving ? null : onRemove,
            icon: isRemoving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.bookmark_remove_outlined),
          ),
        ],
      ),
    );
  }
}
