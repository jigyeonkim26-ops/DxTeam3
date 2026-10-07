class MemoryCreateRequest {
  const MemoryCreateRequest({
    required this.placeId,
    required this.content,
    required this.visitedOn,
    required this.emotionCode,
  });

  final int placeId;
  final String content;
  final DateTime visitedOn;
  final String emotionCode;

  Map<String, Object> toJson() => {
        'place_id': placeId,
        'content': content,
        'visited_on': _dateOnly(visitedOn),
        'emotion_code': emotionCode,
      };

  static String _dateOnly(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}
