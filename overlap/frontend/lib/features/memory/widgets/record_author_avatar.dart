import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_config.dart';
import '../../../core/network/api_transport.dart';

class RecordAuthorAvatar extends StatelessWidget {
  const RecordAuthorAvatar({
    super.key,
    required this.name,
    required this.profileImagePath,
    required this.radius,
    this.backgroundColor = AppColors.softMint,
    this.initialFontSize,
  });

  final String name;
  final String? profileImagePath;
  final double radius;
  final Color backgroundColor;
  final double? initialFontSize;

  @override
  Widget build(BuildContext context) {
    final initial = name.isEmpty ? '?' : name.substring(0, 1);
    final token = ApiTransport.accessToken;
    final path = profileImagePath;
    final imageUrl = path == null || path.isEmpty
        ? null
        : path.startsWith('http://') || path.startsWith('https://')
        ? path
        : '${ApiConfig.baseUrl}$path';
    final provider = imageUrl == null || token == null || token.isEmpty
        ? null
        : NetworkImage(imageUrl, headers: {'Authorization': 'Bearer $token'});

    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      foregroundColor: AppColors.deepNavy,
      child: provider == null
          ? _AvatarInitial(initial: initial, fontSize: initialFontSize)
          : ClipOval(
              child: SizedBox.expand(
                child: Image(
                  image: provider,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _AvatarInitial(
                    initial: initial,
                    fontSize: initialFontSize,
                  ),
                ),
              ),
            ),
    );
  }
}

class _AvatarInitial extends StatelessWidget {
  const _AvatarInitial({required this.initial, this.fontSize});

  final String initial;
  final double? fontSize;

  @override
  Widget build(BuildContext context) => Text(
    initial,
    style: TextStyle(fontWeight: FontWeight.w700, fontSize: fontSize),
  );
}
