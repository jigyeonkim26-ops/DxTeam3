import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_config.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';

class RecordPhoto extends StatelessWidget {
  const RecordPhoto({super.key, required this.paths, this.height = 176});
  final List<String> paths;
  final double height;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
    child: SizedBox(
      height: height,
      width: double.infinity,
      child: paths.isEmpty
          ? const ColoredBox(color: AppColors.paleMint)
          : PageView(
              children: paths
                  .map(
                    (path) => Image.network(
                      '${ApiConfig.baseUrl}$path',
                      headers: {
                        'Authorization':
                            'Bearer ${ApiClient.accessToken ?? ''}',
                      },
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: AppColors.paleMint,
                        child: Center(child: Text('사진을 불러오지 못했습니다.')),
                      ),
                    ),
                  )
                  .toList(),
            ),
    ),
  );
}
