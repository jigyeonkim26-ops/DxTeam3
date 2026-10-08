import 'package:flutter_test/flutter_test.dart';
import 'package:overlap_app/features/group/models/group_list_item_data.dart';

void main() {
  test('keeps unavailable group statistics distinct from zero', () {
    const group = GroupListItemData(
      id: '1',
      name: 'API group',
      memberCount: 2,
      placeCount: null,
      newRecordCount: null,
      recordCount: null,
      inviteCode: '',
    );

    expect(group.placeCount, isNull);
    expect(group.newRecordCount, isNull);
    expect(group.recordCount, isNull);

    final renamed = group.copyWith(name: 'Renamed API group');
    expect(renamed.placeCount, isNull);
    expect(renamed.recordCount, isNull);
  });
}
