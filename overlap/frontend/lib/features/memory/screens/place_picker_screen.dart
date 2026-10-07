import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/place.dart';
import '../../map/widgets/kakao_map_webview.dart';

class PlacePickerScreen extends StatefulWidget {
  const PlacePickerScreen({super.key, this.initialPlace});

  final Place? initialPlace;

  @override
  State<PlacePickerScreen> createState() => _PlacePickerScreenState();
}

class _PlacePickerScreenState extends State<PlacePickerScreen> {
  static const _defaultLatitude = 37.5665;
  static const _defaultLongitude = 126.9250;

  late final TextEditingController _placeNameController;
  late double _latitude;
  late double _longitude;

  @override
  void initState() {
    super.initState();
    final initialPlace = widget.initialPlace;
    _placeNameController = TextEditingController(text: initialPlace?.name);
    _latitude = initialPlace?.latitude ?? _defaultLatitude;
    _longitude = initialPlace?.longitude ?? _defaultLongitude;
  }

  @override
  void dispose() {
    _placeNameController.dispose();
    super.dispose();
  }

  void _onLocationChanged(double latitude, double longitude) {
    if (!mounted) return;
    setState(() {
      _latitude = latitude;
      _longitude = longitude;
    });
  }

  void _showCurrentLocationUnavailable() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('현재 위치 기능은 추후 연결됩니다.')));
  }

  void _confirmPlace() {
    final placeName = _placeNameController.text.trim();
    if (placeName.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('장소명을 입력해 주세요.')));
      return;
    }

    Navigator.of(context).pop(
      Place(
        id: 'selected-${_latitude.toStringAsFixed(6)}-${_longitude.toStringAsFixed(6)}',
        name: placeName,
        latitude: _latitude,
        longitude: _longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(title: const Text('장소 선택'), centerTitle: true),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
              child: SizedBox(
                height: 300,
                child: KakaoMapWebView(
                  selectionMode: true,
                  initialLatitude: _latitude,
                  initialLongitude: _longitude,
                  onLocationChanged: _onLocationChanged,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              '핀을 움직이거나 지도를 탭해 정확한 위치를 선택해 주세요.',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '선택 위치  ${_latitude.toStringAsFixed(6)}, ${_longitude.toStringAsFixed(6)}',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton.icon(
              onPressed: _showCurrentLocationUnavailable,
              icon: const Icon(Icons.my_location_outlined),
              label: const Text('현재 위치 다시 찾기'),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              '장소 이름',
              style: TextStyle(
                color: AppColors.ink,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextField(
              controller: _placeNameController,
              maxLength: 50,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(hintText: '장소명을 입력해 주세요.'),
              onSubmitted: (_) => _confirmPlace(),
            ),
            const SizedBox(height: AppSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _confirmPlace,
                child: const Text('이 장소로 선택하기'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
