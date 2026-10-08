enum MapFilter {
  mine('내 기록');

  const MapFilter(this.label);

  final String label;

  static const selectableFilters = <MapFilter>[mine];
}
