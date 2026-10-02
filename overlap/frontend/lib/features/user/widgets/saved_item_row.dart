import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../models/saved_item_data.dart';

class SavedItemRow extends StatelessWidget {
  const SavedItemRow({super.key, required this.item, required this.onTap});
  final SavedItemData item;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.divider)),
        ),
        child: Row(
          children: [
            Container(
              width: 70,
              height: 70,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: item.itemType == SavedItemType.wishPlace
                    ? AppColors.softMint
                    : AppColors.paleMint,
                borderRadius: const BorderRadius.all(Radius.circular(14)),
              ),
              child: Text(
                item.thumbnailLabel,
                style: const TextStyle(
                  color: AppColors.deepNavy,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: Theme.of(context).textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    item.description,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(fontSize: 12),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    item.metaText,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
