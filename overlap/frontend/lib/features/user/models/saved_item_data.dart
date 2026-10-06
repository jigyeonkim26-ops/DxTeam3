enum SavedItemType { wishPlace, myRecord }

class SavedItemData {
  const SavedItemData({
    required this.title,
    required this.description,
    required this.metaText,
    required this.itemType,
    required this.thumbnailLabel,
  });
  final String title;
  final String description;
  final String metaText;
  final SavedItemType itemType;
  final String thumbnailLabel;
}
