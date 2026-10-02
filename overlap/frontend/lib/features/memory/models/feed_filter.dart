enum FeedFilter {
  all('전체 모임'),
  yeonnam('연남 산책단'),
  neighborhood('동네 친구들'),
  travel('여행팟'),
  mine('내 기록만 보기');

  const FeedFilter(this.label);

  final String label;
}
