import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'api_client.dart';

/// Loads private API images through the shared 401 refresh path.
class AuthenticatedImage extends StatefulWidget {
  const AuthenticatedImage({
    super.key,
    required this.url,
    this.fit,
    this.width,
    this.height,
    this.errorBuilder,
  });

  final String url;
  final BoxFit? fit;
  final double? width;
  final double? height;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;

  @override
  State<AuthenticatedImage> createState() => _AuthenticatedImageState();
}

class _AuthenticatedImageState extends State<AuthenticatedImage> {
  late Future<Uint8List> _bytes;

  @override
  void initState() {
    super.initState();
    _bytes = _load();
  }

  Future<Uint8List> _load() async {
    final response = await ApiClient.authenticatedGet(Uri.parse(widget.url));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException('이미지를 불러오지 못했습니다.', statusCode: response.statusCode);
    }
    return response.bodyBytes;
  }

  @override
  void didUpdateWidget(covariant AuthenticatedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _bytes = _load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return widget.errorBuilder?.call(context, snapshot.error!, null) ??
            const SizedBox.shrink();
      }
      final bytes = snapshot.data;
      if (bytes == null) return const SizedBox.shrink();
      return Image.memory(
        bytes,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: widget.errorBuilder,
      );
    },
  );
}
