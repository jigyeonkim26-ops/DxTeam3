enum FeedFilter {
  all('전체'),
  mine('내 기록');

  const FeedFilter(this.label);

  final String label;

  static const selectableFilters = <FeedFilter>[mine];
}
