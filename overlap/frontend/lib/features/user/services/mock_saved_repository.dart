import '../models/saved_item_data.dart';

/// Saved data is shown only when supplied by the API.
abstract final class MockSavedRepository {
  static const List<SavedItemData> wishPlaces = [];
  static const List<SavedItemData> myRecords = [];
}
