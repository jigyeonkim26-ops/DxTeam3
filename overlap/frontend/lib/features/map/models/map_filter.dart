class MapFilter {
  const MapFilter.group(this.groupId, this.label, {this.pinColorValue});
  const MapFilter._mine()
    : groupId = null,
      label = '내 기록',
      pinColorValue = null;
  static const mine = MapFilter._mine();
  final int? groupId;
  final String label;
  final int? pinColorValue;
  @override
  bool operator ==(Object other) =>
      other is MapFilter && groupId == other.groupId;
  @override
  int get hashCode => groupId.hashCode;
}
