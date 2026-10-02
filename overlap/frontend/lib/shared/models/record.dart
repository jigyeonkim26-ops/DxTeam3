import 'emotion.dart';
import 'group.dart';
import 'place.dart';
import 'user.dart';

/// 장소에서 남긴 한 건의 기억(기록)입니다.
class Record {
  const Record({
    required this.id,
    required this.author,
    required this.place,
    required this.createdAt,
    required this.content,
    required this.emotion,
    this.imagePaths = const [],
    this.sharedGroups = const [],
    this.isPrivate = false,
    this.likeCount = 0,
    this.commentCount = 0,
  });

  final String id;
  final User author;
  final Place place;
  final DateTime createdAt;
  final String content;
  final Emotion emotion;
  final List<String> imagePaths;
  final List<Group> sharedGroups;
  final bool isPrivate;
  final int likeCount;
  final int commentCount;
}
