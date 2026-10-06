import '../../../shared/models/place.dart';

class AiPlaceRecommendation {
  const AiPlaceRecommendation({
    required this.place,
    required this.keywords,
    required this.reason,
    required this.imageSeed,
  });

  final Place place;
  final List<String> keywords;
  final String reason;
  final int imageSeed;
}

/// 실제 AI 분석 전 추천 화면 흐름을 확인하기 위한 더미 추천 세트입니다.
const mockAiRecommendationSets = [
  [
    AiPlaceRecommendation(
      place: Place(
        id: 'ai-seoul-forest',
        name: '서울숲',
        latitude: 37.5444,
        longitude: 127.0374,
        address: '서울 성동구 성수동',
      ),
      keywords: ['산책', '자연', '친구'],
      reason: '산책과 여유로운 분위기를 좋아했던 기록과 잘 맞아요.',
      imageSeed: 0,
    ),
    AiPlaceRecommendation(
      place: Place(
        id: 'ai-nodeul-island',
        name: '노들섬',
        latitude: 37.5178,
        longitude: 126.9583,
        address: '서울 용산구 양녕로 445',
      ),
      keywords: ['노을', '한강', '산책'],
      reason: '노을이 인상적이었던 기록을 바탕으로 추천했어요.',
      imageSeed: 1,
    ),
    AiPlaceRecommendation(
      place: Place(
        id: 'ai-mangwon-hangang',
        name: '망원한강공원',
        latitude: 37.5527,
        longitude: 126.8940,
        address: '서울 마포구 마포나루길 467',
      ),
      keywords: ['노을', '피크닉', '친구'],
      reason: '친구와 함께한 야외 기록의 만족도가 높았어요.',
      imageSeed: 2,
    ),
    AiPlaceRecommendation(
      place: Place(
        id: 'ai-yeonhui-cafe',
        name: '연희동 조용한 카페',
        latitude: 37.5682,
        longitude: 126.9308,
        address: '서울 서대문구 연희동',
      ),
      keywords: ['카페', '조용함', '대화'],
      reason: '조용한 카페에서 남긴 긍정 기록과 비슷한 장소예요.',
      imageSeed: 3,
    ),
  ],
  [
    AiPlaceRecommendation(
      place: Place(
        id: 'ai-seongsu-cafe-street',
        name: '성수 카페거리',
        latitude: 37.5446,
        longitude: 127.0559,
        address: '서울 성동구 성수동',
      ),
      keywords: ['카페', '산책', '발견'],
      reason: '새로운 골목과 카페를 발견한 순간을 좋아했던 흐름과 닮았어요.',
      imageSeed: 3,
    ),
    AiPlaceRecommendation(
      place: Place(
        id: 'ai-seonyudo-park',
        name: '선유도공원',
        latitude: 37.5438,
        longitude: 126.9007,
        address: '서울 영등포구 선유로 343',
      ),
      keywords: ['자연', '산책', '고요함'],
      reason: '조용히 걷고 쉬었던 기록의 편안한 분위기를 이어갈 수 있어요.',
      imageSeed: 0,
    ),
    AiPlaceRecommendation(
      place: Place(
        id: 'ai-ichon-hangang',
        name: '이촌한강공원',
        latitude: 37.5184,
        longitude: 126.9738,
        address: '서울 용산구 이촌동',
      ),
      keywords: ['한강', '노을', '여유'],
      reason: '하늘과 물가를 오래 바라본 긍정적인 기억을 반영했어요.',
      imageSeed: 1,
    ),
    AiPlaceRecommendation(
      place: Place(
        id: 'ai-bukchon',
        name: '북촌한옥마을',
        latitude: 37.5826,
        longitude: 126.9830,
        address: '서울 종로구 북촌',
      ),
      keywords: ['골목', '대화', '기억'],
      reason: '친구와 천천히 걸으며 이야기를 나눈 기록과 잘 어울려요.',
      imageSeed: 2,
    ),
  ],
];
