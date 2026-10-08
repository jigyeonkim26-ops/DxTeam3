import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';

class PhotoPlaceholderPicker extends StatelessWidget {
  const PhotoPlaceholderPicker({
    super.key,
    required this.photos,
    required this.onAddCamera,
    required this.onAddGallery,
    required this.onRemove,
  });

  final List<XFile> photos;
  final VoidCallback onAddCamera;
  final VoidCallback onAddGallery;
  final ValueChanged<XFile> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (photos.isEmpty)
          Container(
            height: 148,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.paleMint,
              borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            ),
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_a_photo_outlined, color: AppColors.deepNavy),
                  SizedBox(height: AppSpacing.xs),
                  Text('사진을 추가해 보세요'),
                ],
              ),
            ),
          )
        else
          SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
              itemBuilder: (context, index) => _PhotoPreview(
                id: photos[index],
                index: index,
                onRemove: () => onRemove(photos[index]),
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onAddCamera,
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('카메라'),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onAddGallery,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('갤러리'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({
    required this.id,
    required this.index,
    required this.onRemove,
  });

  final XFile id;
  final int index;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 112,
      child: Stack(
        children: [
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
              child: FutureBuilder(
                future: id.readAsBytes(),
                builder: (context, snapshot) => snapshot.hasData
                    ? Image.memory(
                        snapshot.data!,
                        fit: BoxFit.cover,
                        width: 104,
                        height: 104,
                      )
                    : const Center(child: CircularProgressIndicator()),
              ),
            ),
          ),
          Positioned(
            top: 3,
            right: 0,
            child: Material(
              color: AppColors.surface,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onRemove,
                customBorder: const CircleBorder(),
                child: const SizedBox(
                  width: 28,
                  height: 28,
                  child: Icon(Icons.close, size: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
