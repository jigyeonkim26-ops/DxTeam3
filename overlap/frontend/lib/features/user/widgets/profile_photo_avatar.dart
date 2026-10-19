import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_config.dart';
import '../../../core/network/api_transport.dart';
import '../../../core/network/authenticated_image.dart';

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

    final useLocal = imagePath != null && imagePath.isNotEmpty;
    final useRemote =
        !useLocal && showRemote && token != null && token.isNotEmpty;

    return ClipOval(
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: useLocal
            ? Image(
                image: FileImage(File(imagePath)),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    _DefaultProfilePhoto(iconSize: iconSize),
              )
            : useRemote
            ? AuthenticatedImage(
                url: '${ApiConfig.baseUrl}/auth/me/photo?v=$revision',
                width: diameter,
                height: diameter,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    _DefaultProfilePhoto(iconSize: iconSize),
              )
            : _DefaultProfilePhoto(iconSize: iconSize),
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
