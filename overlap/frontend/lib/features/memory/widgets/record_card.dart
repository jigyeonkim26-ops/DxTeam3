import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/record.dart';

class RecordCard extends StatelessWidget {
  const RecordCard({
    super.key,
    required this.record,
    required this.isLiked,
    required this.onTap,
    required this.onLikeTap,
    required this.onCommentTap,
    required this.onPlaceTap,
  });

  final Record record;
  final bool isLiked;
  final VoidCallback onTap;
  final VoidCallback onLikeTap;
  final VoidCallback onCommentTap;
  final VoidCallback onPlaceTap;

  @override
  Widget build(BuildContext context) {
    final likeCount = record.likeCount + (isLiked ? 1 : 0);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Avatar(name: record.author.name),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.author.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          _formattedTime(record.createdAt),
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    record.emotion.emoji,
                    style: const TextStyle(fontSize: 22),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton.icon(
                onPressed: onPlaceTap,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.deepNavy,
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.location_on_outlined, size: 17),
                label: Text(
                  record.place.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(record.content, style: const TextStyle(height: 1.5)),
              if (record.imagePaths.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                _RecordPhotos(key: ValueKey(record.id), record: record),
                const SizedBox(height: AppSpacing.sm),
              ],
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  _EmotionChip(record: record),
                  for (final group in record.sharedGroups)
                    _GroupChip(label: group.name),
                ],
              ),
              const Divider(height: AppSpacing.lg),
              Row(
                children: [
                  _ActionButton(
                    icon: isLiked ? Icons.favorite : Icons.favorite_border,
                    label: '공감 $likeCount',
                    color: isLiked ? AppColors.coral : AppColors.muted,
                    onTap: onLikeTap,
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  _ActionButton(
                    icon: Icons.chat_bubble_outline,
                    label: '댓글 ${record.commentCount}',
                    color: AppColors.muted,
                    onTap: onCommentTap,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formattedTime(DateTime time) {
    final now = DateTime.now();
    final isToday =
        now.year == time.year && now.month == time.month && now.day == time.day;
    final minute = time.minute.toString().padLeft(2, '0');
    return isToday ? '오늘 ${time.hour}:$minute' : '${time.month}월 ${time.day}일';
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 20,
      backgroundColor: AppColors.softMint,
      foregroundColor: AppColors.deepNavy,
      child: Text(
        name.substring(0, 1),
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _RecordPhotos extends StatefulWidget {
  const _RecordPhotos({super.key, required this.record});

  final Record record;

  @override
  State<_RecordPhotos> createState() => _RecordPhotosState();
}

class _RecordPhotosState extends State<_RecordPhotos> {
  static const _viewportFraction = 0.9;
  late final PageController _pageController;
  final Map<String, double> _aspectRatioCache = {};
  var _currentPage = 0;

  Record get record => widget.record;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: _viewportFraction);
    for (final path in record.imagePaths) {
      _resolveAspectRatio(path);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final path = record.imagePaths[_currentPage];
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = record.imagePaths.length == 1
            ? constraints.maxWidth
            : constraints.maxWidth * _viewportFraction - AppSpacing.xs;
        final ratio = _aspectRatioCache[path] ?? 1;
        final height = itemWidth / ratio;
        return AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: SizedBox(
            height: height,
            child: record.imagePaths.length == 1
                ? _RecordImage(path: path, fallbackColors: _colorsFor(0))
                : PageView.builder(
                    controller: _pageController,
                    padEnds: false,
                    itemCount: record.imagePaths.length,
                    onPageChanged: (index) =>
                        setState(() => _currentPage = index),
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xs),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: _RecordImage(
                              path: record.imagePaths[index],
                              fallbackColors: _colorsFor(index),
                            ),
                          ),
                          Positioned(
                            top: AppSpacing.xs,
                            right: AppSpacing.sm,
                            child: _PageIndicator(
                              currentPage: _currentPage,
                              pageCount: record.imagePaths.length,
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

  void _resolveAspectRatio(String path) {
    if (!path.startsWith('assets/')) return;
    final stream = AssetImage(path).resolve(ImageConfiguration.empty);
    stream.addListener(
      ImageStreamListener((info, _) {
        final ratio = info.image.width / info.image.height;
        if (mounted && _aspectRatioCache[path] != ratio) {
          setState(() => _aspectRatioCache[path] = ratio);
        }
      }),
    );
  }

  List<Color> _colorsFor(int index) {
    if (record.id == 'debug-multi-image-preview') {
      return const [
        [Color(0xFF5E8EA8), Color(0xFFB9D9E8)],
        [Color(0xFFE6B07A), Color(0xFFFF7058)],
        [Color(0xFF86B88C), Color(0xFFDCEFE5)],
      ][index];
    }

    return switch (record.emotion) {
      _ when record.id.contains('coast') => const [
        Color(0xFF5E8EA8),
        Color(0xFFFFB26B),
      ],
      _ when record.id.contains('park') => const [
        Color(0xFF86B88C),
        Color(0xFFDCEFE5),
      ],
      _ when record.id.contains('bakery') => const [
        Color(0xFFE6B07A),
        Color(0xFF9B6A57),
      ],
      _ => const [Color(0xFF9FC4B2), AppColors.deepNavy],
    };
  }
}

class _RecordImage extends StatelessWidget {
  const _RecordImage({required this.path, required this.fallbackColors});

  final String path;
  final List<Color> fallbackColors;

  @override
  Widget build(BuildContext context) {
    if (path.startsWith('assets/')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: Image.asset(
          path,
          width: double.infinity,
          height: double.infinity,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => _PhotoPlaceholder(colors: fallbackColors),
        ),
      );
    }
    return _PhotoPlaceholder(colors: fallbackColors);
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({required this.colors});
  final List<Color> colors;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
      gradient: LinearGradient(colors: colors),
    ),
    child: const Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.sm),
        child: Icon(Icons.image_outlined, color: Colors.white70),
      ),
    ),
  );
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.currentPage, required this.pageCount});

  final int currentPage;
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          '${currentPage + 1} / $pageCount',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _EmotionChip extends StatelessWidget {
  const _EmotionChip({required this.record});

  final Record record;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: AppColors.paleMint,
        borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
      ),
      child: Text('${record.emotion.emoji} ${record.emotion.displayName}'),
    );
  }
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.divider),
        borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
      ),
      child: Text(
        label,
        style: const TextStyle(color: AppColors.muted, fontSize: 12),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
