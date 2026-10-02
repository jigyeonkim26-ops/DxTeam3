import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../models/map_place.dart';

class PlaceMarker extends StatelessWidget {
  const PlaceMarker({
    super.key,
    required this.place,
    required this.isSelected,
    required this.onTap,
  });

  final MapPlace place;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isSelected ? AppColors.deepNavy : AppColors.coral;
    return Semantics(
      button: true,
      label: '${place.name}, 기록 ${place.recordCount}개',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 112),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x3314324A),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: Colors.white,
                      size: 15,
                    ),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        '${place.name} ${place.recordCount}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_drop_down, color: color, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
