import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../shared/models/emotion.dart';
import '../../../shared/models/group.dart';
import '../../../shared/models/place.dart';
import '../../../shared/models/record.dart';
import '../../../shared/models/user.dart';
import '../../memory/screens/record_detail_screen.dart';
import '../widgets/place_record_preview_card.dart';

/// 특정 장소에 쌓인 기록을 보여주는 독립 화면입니다.
class PlaceDetailScreen extends StatefulWidget {
  const PlaceDetailScreen({super.key});

  @override
  State<PlaceDetailScreen> createState() => _PlaceDetailScreenState();
}

class _PlaceDetailScreenState extends State<PlaceDetailScreen> {
  bool _isSaved = false;

  static const _place = Place(
    id: 'place-yeonnam-cafe',
    name: '연남동 작은 카페',
    latitude: 37.5665,
    longitude: 126.9250,
    address: '서울 마포구 연남동',
    recordCount: 3,
  );

  static const _yeonnam = Group(
    id: 'group-yeonnam',
    name: '연남 산책단',
    memberCount: 3,
  );

  static const _minji = User(id: 'user-minji', name: '민지');
  static const _seoyeon = User(id: 'user-seoyeon', name: '서연');
  static const _doyoon = User(id: 'user-doyoon', name: '도윤');

  static final List<Record> _records = [
    Record(
      id: 'place-record-rain',
      author: _minji,
      place: _place,
      createdAt: DateTime(2026, 10, 2, 15, 10),
      content: '비가 그친 뒤 창가 자리에 앉아 잠깐 쉬어갔어. 다음에는 같이 와서 더 오래 이야기하자.',
      emotion: Emotion.good,
      imagePaths: const ['place-rain'],
      sharedGroups: const [_yeonnam],
      likeCount: 4,
      commentCount: 2,
    ),
    Record(
      id: 'place-record-sun',
      author: _seoyeon,
      place: _place,
      createdAt: DateTime(2026, 10, 2, 15, 0),
      content: '같은 장소지만 오후 빛이 더 따뜻했다. 오늘의 기억도 천천히 남겨두고 싶어.',
      emotion: Emotion.excellent,
      imagePaths: const ['place-sun'],
      sharedGroups: const [_yeonnam],
      likeCount: 3,
      commentCount: 2,
    ),
    Record(
      id: 'place-record-calm',
      author: _doyoon,
      place: _place,
      createdAt: DateTime(2026, 10, 1, 18, 20),
      content: '창밖을 보면서 오늘 걸었던 길을 다시 이야기했다. 조용해서 더 좋았던 오후.',
      emotion: Emotion.okay,
      imagePaths: const ['place-calm'],
      sharedGroups: const [_yeonnam],
      likeCount: 1,
      commentCount: 0,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ColoredBox(
        color: AppColors.paper,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.lg,
          ),
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.arrow_back),
                  tooltip: '뒤로가기',
                ),
                const SizedBox(width: AppSpacing.xxs),
                const Expanded(
                  child: Text(
                    '장소 상세',
                    style: TextStyle(
                      color: AppColors.deepNavy,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _isSaved = !_isSaved),
                  icon: Icon(
                    _isSaved ? Icons.bookmark : Icons.bookmark_border,
                    color: _isSaved ? AppColors.coral : AppColors.deepNavy,
                  ),
                  tooltip: _isSaved ? '저장 취소' : '장소 저장',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _PlaceSummary(place: _place, isSaved: _isSaved),
            const SizedBox(height: AppSpacing.lg),
            Text(
              '이 장소에 쌓인 기억',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.deepNavy,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '친구들이 같은 장소에서 남긴 순간들이에요.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.muted,
                fontSize: 14,
                fontWeight: FontWeight.w400,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final record in _records) ...[
              PlaceRecordPreviewCard(
                record: record,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => RecordDetailScreen(record: record),
                    ),
                  );
                },
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlaceSummary extends StatelessWidget {
  const _PlaceSummary({required this.place, required this.isSaved});

  final Place place;
  final bool isSaved;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'OVERLAPPED PLACE',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              place.name,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 17),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: Text(
                    place.address ?? '주소 정보 없음',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              height: 126,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF9FC4B2), AppColors.deepNavy],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppSpacing.buttonRadius),
              ),
              child: const Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: EdgeInsets.all(AppSpacing.sm),
                  child: Text(
                    '창가 자리와 따뜻한 오후',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                _SummaryChip(
                  icon: Icons.auto_stories_outlined,
                  label: '기록 ${place.recordCount}개',
                ),
                const SizedBox(width: AppSpacing.xs),
                _SummaryChip(
                  icon: isSaved ? Icons.bookmark : Icons.bookmark_border,
                  label: isSaved ? '저장됨' : '저장하기',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: AppColors.paleMint,
        borderRadius: BorderRadius.circular(AppSpacing.pillRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.deepNavy),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.deepNavy,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
