import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/network/api_client.dart';
import '../models/saved_place.dart';
import '../services/saved_places_api.dart';

class SavedScreen extends StatefulWidget {
  const SavedScreen({super.key, this.savedPlacesApi});

  final SavedPlacesApi? savedPlacesApi;

  @override
  State<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends State<SavedScreen> {
  late final SavedPlacesApi _savedPlacesApi;
  List<SavedPlace> _places = const [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _savedPlacesApi = widget.savedPlacesApi ?? SavedPlacesApi();
    SavedPlacesApi.revision.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    SavedPlacesApi.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      final places = await _savedPlacesApi.list();
      if (!mounted) return;
      setState(() {
        _places = places;
        _isLoading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('저장한 장소')),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
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
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) {
      return Center(
        child: TextButton(
          onPressed: _load,
          child: Text('$_errorMessage 다시 시도'),
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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      itemCount: _places.length,
      separatorBuilder: (_, _) => const Divider(color: AppColors.divider),
      itemBuilder: (_, index) => _SavedPlaceRow(place: _places[index]),
    );
  }
}

class _SavedPlaceRow extends StatelessWidget {
  const _SavedPlaceRow({required this.place});

  final SavedPlace place;

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
        ],
      ),
    );
  }
}
