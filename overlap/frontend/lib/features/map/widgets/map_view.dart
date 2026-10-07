import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../models/current_location.dart';
import '../models/map_place.dart';
import '../models/map_search_place.dart';
import 'kakao_map_webview.dart';

/// 현재는 가벼운 placeholder를 그리며, 추후 Kakao Map View로 교체할 영역입니다.
class MapView extends StatelessWidget {
  const MapView({
    super.key,
    required this.isSatellite,
    required this.places,
    required this.selectedPlaceId,
    required this.searchPlace,
    required this.currentLocation,
    required this.currentLocationRequestId,
    required this.onPlaceTap,
  });

  final bool isSatellite;
  final List<MapPlace> places;
  final String? selectedPlaceId;
  final MapSearchPlace? searchPlace;
  final CurrentLocation? currentLocation;
  final int currentLocationRequestId;
  final ValueChanged<MapPlace> onPlaceTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: !kIsWeb && defaultTargetPlatform == TargetPlatform.android
              ? KakaoMapWebView(
                  places: places,
                  searchPlace: searchPlace,
                  currentLocation: currentLocation,
                  currentLocationRequestId: currentLocationRequestId,
                  onPlaceTap: onPlaceTap,
                )
              : CustomPaint(
                  painter: _MapPlaceholderPainter(isSatellite: isSatellite),
                ),
        ),
        Positioned(
          left: 16,
          bottom: 18,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surface.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Text(
                'Kakao Map 연결 전 미리보기',
                style: TextStyle(color: AppColors.muted, fontSize: 10),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MapPlaceholderPainter extends CustomPainter {
  const _MapPlaceholderPainter({required this.isSatellite});

  final bool isSatellite;

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = LinearGradient(
        colors: isSatellite
            ? const [Color(0xFF738A73), Color(0xFF445E5C), Color(0xFF8D9270)]
            : const [Color(0xFFDCEFE5), Color(0xFFF4F1E7), Color(0xFFC9E2D5)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, background);

    final road = Paint()
      ..color = isSatellite
          ? Colors.white.withValues(alpha: 0.35)
          : Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15
      ..strokeCap = StrokeCap.round;
    final sideRoad = Paint()
      ..color = isSatellite
          ? Colors.white.withValues(alpha: 0.22)
          : const Color(0xFFE8E5DA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    final primaryPath = Path()
      ..moveTo(-20, size.height * 0.22)
      ..cubicTo(
        size.width * 0.24,
        size.height * 0.28,
        size.width * 0.48,
        size.height * 0.10,
        size.width + 20,
        size.height * 0.22,
      );
    final secondaryPath = Path()
      ..moveTo(size.width * 0.16, -20)
      ..cubicTo(
        size.width * 0.32,
        size.height * 0.30,
        size.width * 0.62,
        size.height * 0.55,
        size.width * 0.54,
        size.height + 20,
      );
    final thirdPath = Path()
      ..moveTo(-20, size.height * 0.76)
      ..quadraticBezierTo(
        size.width * 0.42,
        size.height * 0.50,
        size.width + 20,
        size.height * 0.72,
      );
    canvas.drawPath(primaryPath, road);
    canvas.drawPath(secondaryPath, sideRoad);
    canvas.drawPath(thirdPath, sideRoad);

    if (!isSatellite) {
      final parkPaint = Paint()..color = const Color(0xFFB9D8BA);
      canvas.drawCircle(
        Offset(size.width * 0.78, size.height * 0.36),
        size.width * 0.18,
        parkPaint,
      );
      canvas.drawCircle(
        Offset(size.width * 0.16, size.height * 0.76),
        size.width * 0.14,
        parkPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MapPlaceholderPainter oldDelegate) =>
      oldDelegate.isSatellite != isSatellite;
}
