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

  factory Record.fromJson(Map<String, dynamic> json) {
    final author = json['author'] as Map;
    final place = json['place'] as Map;
    return Record(
      id: '${json['id']}',
      author: User(
        id: '${author['id']}',
        name: author['name'] as String,
        profileImagePath: author['profile_image_url'] as String?,
      ),
      place: Place(
        id: '${place['id']}',
        name: place['name'] as String,
        address: place['address'] as String?,
        latitude: (place['latitude'] as num).toDouble(),
        longitude: (place['longitude'] as num).toDouble(),
      ),
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      content: json['content'] as String,
      emotion: Emotion.fromApi(json['emotion']),
      imagePaths: (json['photo_urls'] as List? ?? const []).cast<String>(),
      isPrivate: json['is_private'] as bool,
      sharedGroups: (json['shared_groups'] as List)
          .map((g) => Group(id: '${g['id']}', name: g['name'] as String))
          .toList(),
    );
  }
}
