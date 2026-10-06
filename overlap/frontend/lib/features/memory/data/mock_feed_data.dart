import '../../../shared/models/emotion.dart';
import '../../../shared/models/group.dart';
import '../../../shared/models/place.dart';
import '../../../shared/models/record.dart';
import '../../../shared/models/user.dart';

const currentFeedUser = User(id: 'user-seoyeon', name: '서연');

const _minji = User(id: 'user-minji', name: '민지');
const _jiwoo = User(id: 'user-jiwoo', name: '지우');
const _haneul = User(id: 'user-haneul', name: '하늘');
const _doyoon = User(id: 'user-doyoon', name: '도윤');

const yeonnamGroup = Group(
  id: 'group-yeonnam',
  name: '연남 산책단',
  description: '같이 걷고 기록하는 모임',
  memberCount: 3,
);
const neighborhoodGroup = Group(
  id: 'group-neighborhood',
  name: '동네 친구들',
  description: '우리 동네의 좋은 장소',
  memberCount: 5,
);
const travelGroup = Group(
  id: 'group-travel',
  name: '여행팟',
  description: '함께 떠난 여행의 순간',
  memberCount: 4,
);

/// API 연결 전 피드 UI에 사용하는 최신순 목업 기록입니다.
final List<Record> mockFeedRecords = [
  Record(
    id: 'record-minji-cafe',
    author: _minji,
    place: const Place(
      id: 'place-yeonnam-cafe',
      name: '연남동 작은 카페',
      latitude: 37.5665,
      longitude: 126.9250,
      address: '서울 마포구 연남동',
      recordCount: 4,
    ),
    createdAt: DateTime(2026, 10, 2, 15, 10),
    content: '비가 그쳐서 테라스 자리로 옮겼어. 다음엔 여기서 오래 앉아 있자.',
    emotion: Emotion.good,
    imagePaths: const ['feed-cafe'],
    sharedGroups: const [yeonnamGroup],
    likeCount: 2,
    commentCount: 1,
  ),
  Record(
    id: 'record-seoyeon-cafe',
    author: currentFeedUser,
    place: const Place(
      id: 'place-yeonnam-cafe',
      name: '연남동 작은 카페',
      latitude: 37.5665,
      longitude: 126.9250,
      address: '서울 마포구 연남동',
      recordCount: 4,
    ),
    createdAt: DateTime(2026, 10, 2, 15, 0),
    content: '비 오는 날, 창가 자리. 오늘의 산책은 여기서 잠시 쉬어가기로.',
    emotion: Emotion.excellent,
    imagePaths: const ['feed-rain'],
    sharedGroups: const [yeonnamGroup],
    likeCount: 3,
    commentCount: 2,
  ),
  Record(
    id: 'record-seoyeon-park',
    author: currentFeedUser,
    place: const Place(
      id: 'place-neighborhood-park',
      name: '동네 작은 공원',
      latitude: 37.5590,
      longitude: 126.9170,
      address: '서울 마포구',
      recordCount: 2,
    ),
    createdAt: DateTime(2026, 10, 2, 13, 40),
    content: '햇살이 좋아서 오래 걸었어. 벤치에 앉아 있던 시간이 특히 좋았다.',
    emotion: Emotion.good,
    imagePaths: const ['feed-park'],
    sharedGroups: const [neighborhoodGroup],
    likeCount: 4,
    commentCount: 2,
  ),
  Record(
    id: 'record-jiwoo-bakery',
    author: _jiwoo,
    place: const Place(
      id: 'place-alley-bakery',
      name: '골목길 베이커리',
      latitude: 37.5540,
      longitude: 126.9180,
      address: '서울 마포구',
      recordCount: 1,
    ),
    createdAt: DateTime(2026, 10, 1, 18, 20),
    content: '퇴근길에 들른 곳인데 생각보다 분위기가 좋았어. 빵도 따뜻했어.',
    emotion: Emotion.okay,
    imagePaths: const ['feed-bakery'],
    sharedGroups: const [neighborhoodGroup],
    likeCount: 1,
    commentCount: 0,
  ),
  Record(
    id: 'record-haneul-coast',
    author: _haneul,
    place: const Place(
      id: 'place-jeju-coast',
      name: '제주 해안 산책로',
      latitude: 33.4996,
      longitude: 126.5312,
      address: '제주특별자치도 제주시',
      recordCount: 3,
    ),
    createdAt: DateTime(2026, 10, 1, 21, 10),
    content: '여행 첫날의 마지막 풍경. 사진보다 직접 본 하늘이 더 선명했어.',
    emotion: Emotion.excellent,
    imagePaths: const ['feed-coast'],
    sharedGroups: const [travelGroup],
    likeCount: 5,
    commentCount: 3,
  ),
  Record(
    id: 'record-doyoon-oreum',
    author: _doyoon,
    place: const Place(
      id: 'place-jeju-oreum',
      name: '제주 오름 입구',
      latitude: 33.3617,
      longitude: 126.5292,
      address: '제주특별자치도 서귀포시',
      recordCount: 2,
    ),
    createdAt: DateTime(2026, 10, 1, 16, 30),
    content: '바람이 조금 세었지만 같이 걸어서 더 기억에 남아.',
    emotion: Emotion.neutral,
    imagePaths: const ['feed-oreum'],
    sharedGroups: const [travelGroup],
    likeCount: 2,
    commentCount: 1,
  ),
];
