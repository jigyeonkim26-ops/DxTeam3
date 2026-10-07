enum FeedFilter {
  all('내 맞춤 피드'),
  mine('내 기록만 보기');

  const FeedFilter(this.label);
  final String label;
}
