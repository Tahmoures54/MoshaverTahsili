import 'package:flutter_test/flutter_test.dart';
import 'package:moshaver_tahsili/education/mastery_estimator.dart';

void main() {
  test('ignores cards without a topic and malformed review evidence', () {
    final result = estimateTopicMastery([
      {
        'reviewHistory': [
          {'quality': 5},
        ],
      },
      {
        'topic': 'جبر',
        'reviewHistory': [
          {'quality': 8},
          {'quality': '4'},
        ],
      },
    ]);
    expect(result, isEmpty);
  });

  test(
    'uses conservative prior and reports limited evidence for small samples',
    () {
      final result = estimateTopicMastery([
        {
          'topic': 'جبر',
          'reviewHistory': [
            {'quality': 5},
            {'quality': 4},
          ],
        },
      ]).single;
      expect(result.topic, 'جبر');
      expect(result.evidenceCount, 2);
      expect(result.successes, 2);
      expect(result.estimate, closeTo(4.1 / 6.1, 0.0001));
      expect(result.confidence, 'شواهد محدود');
      expect(result.lowerBound, lessThan(result.estimate));
      expect(result.upperBound, greaterThan(result.estimate));
    },
  );

  test('forgotten answers reduce the estimate and count as failures', () {
    final result = estimateTopicMastery([
      {
        'topic': 'فیزیک',
        'reviewHistory': [
          {'quality': 5},
          {'quality': 5},
          {'quality': 1},
        ],
      },
    ]).single;
    expect(result.successes, 2);
    expect(result.evidenceCount, 3);
    expect(result.estimate, lessThan(0.7));
  });

  test('aggregates multiple cards under one topic and sorts weakest first', () {
    final result = estimateTopicMastery([
      {
        'topic': 'هندسه',
        'reviewHistory': [
          {'quality': 1},
          {'quality': 1},
        ],
      },
      {
        'topic': 'هندسه',
        'reviewHistory': [
          {'quality': 4},
        ],
      },
      {
        'topic': 'آمار',
        'reviewHistory': List.generate(10, (_) => {'quality': 5}),
      },
    ]);
    expect(result, hasLength(2));
    expect(result.first.topic, 'هندسه');
    expect(result.last.topic, 'آمار');
    expect(result.last.confidence, 'شواهد محدود');
  });

  test('bounds remain within zero and one for extreme outcomes', () {
    final forgotten = estimateTopicMastery([
      {
        'topic': 'الف',
        'reviewHistory': List.generate(100, (_) => {'quality': 0}),
      },
    ]).single;
    final recalled = estimateTopicMastery([
      {
        'topic': 'ب',
        'reviewHistory': List.generate(100, (_) => {'quality': 5}),
      },
    ]).single;
    for (final value in [forgotten, recalled]) {
      expect(value.lowerBound, inInclusiveRange(0, 1));
      expect(value.upperBound, inInclusiveRange(0, 1));
      expect(value.lowerBound, lessThanOrEqualTo(value.upperBound));
    }
  });
}
