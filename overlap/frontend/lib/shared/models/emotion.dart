/// OVERLAP 기록 작성에 사용하는 여섯 단계 감정입니다.
enum Emotion {
  excellent('최고', '😍', 5),
  good('좋아', '😊', 4),
  okay('괜찮아', '😌', 3),
  neutral('그저 그래', '😐', 2),
  disappointed('아쉬워', '😕', 1),
  poor('별로', '😫', 0);

  const Emotion(this.displayName, this.emoji, this.score);

  final String displayName;
  final String emoji;
  final int score;
}

extension EmotionApiCode on Emotion {
  String get apiCode => switch (this) {
        Emotion.excellent => 'LOVE',
        Emotion.good => 'LIKE',
        Emotion.okay => 'GOOD',
        Emotion.neutral => 'NEUTRAL',
        Emotion.disappointed => 'DISAPPOINTED',
        Emotion.poor => 'BAD',
      };
}
