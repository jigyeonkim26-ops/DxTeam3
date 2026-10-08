import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_config.dart';
import '../../../core/network/api_transport.dart';

/// Displays either the locally selected profile photo or the authenticated
/// user's private profile photo. A failed or missing remote image always falls
/// back to the existing default profile presentation.
class ProfilePhotoAvatar extends StatelessWidget {
  const ProfilePhotoAvatar({
    super.key,
    required this.radius,
    this.localImagePath,
    this.showRemote = true,
    this.revision = 0,
    this.iconSize,
  });

  final double radius;
  final String? localImagePath;
  final bool showRemote;
  final int revision;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final diameter = radius * 2;
    final imagePath = localImagePath;
    final token = ApiTransport.accessToken;

    ImageProvider<Object>? provider;
    if (imagePath != null && imagePath.isNotEmpty) {
      provider = FileImage(File(imagePath));
    } else if (showRemote && token != null && token.isNotEmpty) {
      provider = NetworkImage(
        '${ApiConfig.baseUrl}/auth/me/photo?v=$revision',
        headers: {'Authorization': 'Bearer $token'},
      );
    }

    return ClipOval(
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: provider == null
            ? _DefaultProfilePhoto(iconSize: iconSize)
            : Image(
                image: provider,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    _DefaultProfilePhoto(iconSize: iconSize),
              ),
      ),
    );
  }
}

class _DefaultProfilePhoto extends StatelessWidget {
  const _DefaultProfilePhoto({this.iconSize});

  final double? iconSize;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.softMint,
    child: Icon(Icons.person, color: AppColors.deepNavy, size: iconSize),
  );
}
