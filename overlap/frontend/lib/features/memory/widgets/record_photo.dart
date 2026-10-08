import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_config.dart';

class RecordPhoto extends StatefulWidget {
  const RecordPhoto({super.key, required this.paths, this.height});

  final List<String> paths;
  final double? height;

  @override
  State<RecordPhoto> createState() => _RecordPhotoState();
}

class _RecordPhotoState extends State<RecordPhoto> {
  static const _viewportFraction = .9;
  static final Map<String, double> _aspectRatios = {};

  PageController? _controller;
  var _page = 0;

  @override
  void initState() {
    super.initState();
    _resolveAll();
    if (widget.paths.length > 1) {
      _controller = PageController(viewportFraction: _viewportFraction);
    }
  }

  @override
  void didUpdateWidget(covariant RecordPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paths != widget.paths) {
      _page = 0;
      _resolveAll();
      if (widget.paths.length > 1 && _controller == null) {
        _controller = PageController(viewportFraction: _viewportFraction);
      }
    }
  }

  void _resolveAll() {
    for (final path in widget.paths) {
      if (!_aspectRatios.containsKey(path)) _resolveAspectRatio(path);
    }
  }

  ImageProvider _provider(String path) {
    if (path.startsWith('assets/')) return AssetImage(path);
    final url = path.startsWith('http://') || path.startsWith('https://')
        ? path
        : '${ApiConfig.baseUrl}$path';
    return NetworkImage(
      url,
      headers: {'Authorization': 'Bearer ${ApiClient.accessToken ?? ''}'},
    );
  }

  void _resolveAspectRatio(String path) {
    _provider(path)
        .resolve(ImageConfiguration.empty)
        .addListener(
          ImageStreamListener((image, _) {
            final ratio = image.image.width / image.image.height;
            if (ratio <= 0 || _aspectRatios[path] == ratio) return;
            _aspectRatios[path] = ratio;
            if (mounted) setState(() {});
          }, onError: (_, _) {}),
        );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.paths.isEmpty) return const SizedBox.shrink();
    final activePath = widget.paths[_page.clamp(0, widget.paths.length - 1)];
    final ratio = _aspectRatios[activePath] ?? 1;
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = widget.paths.length == 1
            ? constraints.maxWidth
            : constraints.maxWidth * _viewportFraction - AppSpacing.xs;
        final naturalHeight = itemWidth / ratio;
        final height =
            widget.height ??
            naturalHeight.clamp(120.0, MediaQuery.sizeOf(context).height * .8);
        return AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: SizedBox(
            height: height,
            child: widget.paths.length == 1
                ? _PhotoImage(path: activePath)
                : PageView.builder(
                    controller: _controller,
                    padEnds: false,
                    itemCount: widget.paths.length,
                    onPageChanged: (page) => setState(() => _page = page),
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: _PhotoImage(path: widget.paths[index]),
                          ),
                          if (index == _page)
                            Positioned(
                              top: AppSpacing.xs,
                              right: AppSpacing.xs,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(
                                    AppSpacing.pillRadius,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  child: Text(
                                    '${_page + 1}/${widget.paths.length}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
        );
      },
    );
  }
}

class _PhotoImage extends StatelessWidget {
  const _PhotoImage({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final isAsset = path.startsWith('assets/');
    final url = path.startsWith('http://') || path.startsWith('https://')
        ? path
        : '${ApiConfig.baseUrl}$path';
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      child: isAsset
          ? Image.asset(path, fit: BoxFit.contain, errorBuilder: _fallback)
          : Image.network(
              url,
              headers: {
                'Authorization': 'Bearer ${ApiClient.accessToken ?? ''}',
              },
              fit: BoxFit.contain,
              errorBuilder: _fallback,
            ),
    );
  }

  Widget _fallback(BuildContext _, Object _, StackTrace? _) =>
      const ColoredBox(color: AppColors.paleMint);
}
