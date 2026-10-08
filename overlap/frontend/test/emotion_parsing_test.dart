import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:overlap_app/shared/models/emotion.dart';
import 'package:overlap_app/shared/models/record.dart';

Map<String, dynamic> feedRecord(Object? emotion) => {
  'id': 1,
  'author': {'id': 2, 'name': '테스트 작성자'},
  'place': {
    'id': 3,
    'name': '테스트 장소',
    'address': null,
    'latitude': 37.5,
    'longitude': 127.0,
  },
  'created_at': '2026-10-07T00:00:00Z',
  'content': '',
  'emotion': emotion,
  'is_private': true,
  'photo_urls': [],
  'shared_groups': [],
};

void main() {
  const codes = {
    'EXCELLENT': Emotion.excellent,
    'GOOD': Emotion.good,
    'OKAY': Emotion.okay,
    'NEUTRAL': Emotion.neutral,
    'DISAPPOINTED': Emotion.disappointed,
    'POOR': Emotion.poor,
  };
  for (final entry in codes.entries) {
    test(
      '${entry.key} maps explicitly and supports existing lowercase code',
      () {
        expect(Emotion.fromApi(entry.key), entry.value);
        expect(Emotion.fromApi(entry.key.toLowerCase()), entry.value);
        expect(Emotion.fromApi(' ${entry.key} '), entry.value);
      },
    );
  }
  test('unknown null empty and unexpected types use neutral', () {
    for (final value in [null, '', 'UNKNOWN', 42, false, <String>[]]) {
      expect(Emotion.fromApi(value), Emotion.neutral);
    }
  });
  test('decoded feed parses all records including unknown null and missing emotion', () {
    final payload = jsonDecode(
      jsonEncode({
        'items': [
          for (final code in codes.keys) feedRecord(code),
          feedRecord('UNKNOWN'),
          feedRecord(null),
          feedRecord(null)..remove('emotion'),
        ],
        'total': 9,
      }),
    ) as Map<String, dynamic>;
    final records = (payload['items'] as List)
        .map((item) => Record.fromJson(item as Map<String, dynamic>))
        .toList();
    expect(records.map((record) => record.emotion).toList(), [
      ...codes.values,
      Emotion.neutral,
      Emotion.neutral,
      Emotion.neutral,
    ]);
    expect(records.length, payload['total']);
    expect(records.every((record) => record.imagePaths.isEmpty), isTrue);
    expect(records.first.author.name, '테스트 작성자');
    expect(records.first.isPrivate, isTrue);
  });
}
