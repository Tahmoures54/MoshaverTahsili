import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moshaver_tahsili/education/learning_engine.dart';

Map<String, dynamic> task(
  String id, {
  int minutes = 30,
  String subject = 'ریاضی',
  String? due,
  bool done = false,
}) =>
    {
      'id': id,
      'title': 'کار $id',
      'subject': subject,
      'minutes': minutes,
      'done': done,
      if (due != null) 'dueDate': due,
    };

void main() {
  final today = DateTime(2026, 11, 18); // Wednesday

  group('SM-2 spaced repetition', () {
    test('first and second successful reviews are scheduled for 1 and 6 days', () {
      var state = const ReviewState(ease: 2.5, interval: 0, reps: 0, lapses: 0);
      state = sm2Next(state, 4);
      expect(state.interval, 1);
      expect(state.reps, 1);
      state = sm2Next(state, 4);
      expect(state.interval, 6);
      expect(state.reps, 2);
    });

    test('later successful reviews grow by the ease factor', () {
      const state = ReviewState(ease: 2.5, interval: 6, reps: 2, lapses: 0);
      expect(sm2Next(state, 4).interval, 15);
    });

    test('forgetting restarts the card and records a lapse', () {
      const state = ReviewState(ease: 2.5, interval: 30, reps: 5, lapses: 1);
      final next = sm2Next(state, 1);
      expect(next.interval, 1);
      expect(next.reps, 0);
      expect(next.lapses, 2);
      expect(next.ease, 2.5);
    });

    test('hard answers lower ease but never below 1.3', () {
      var state = const ReviewState(ease: 1.35, interval: 6, reps: 2, lapses: 0);
      for (var i = 0; i < 5; i++) {
        state = sm2Next(state, 3);
      }
      expect(state.ease, 1.3);
    });

    test('easy answers raise ease but are capped at 3.0', () {
      var state = const ReviewState(ease: 2.5, interval: 6, reps: 2, lapses: 0);
      for (var i = 0; i < 50; i++) {
        state = sm2Next(state, 5);
      }
      expect(state.ease, 3.0);
      expect(state.interval, lessThanOrEqualTo(365));
    });

    test('rejects qualities outside 0..5', () {
      const state = ReviewState(ease: 2.5, interval: 0, reps: 0, lapses: 0);
      expect(() => sm2Next(state, 6), throwsRangeError);
      expect(() => sm2Next(state, -1), throwsRangeError);
    });

    test('applyCardReview stores the new schedule and due date', () {
      final now = DateTime(2026, 11, 18, 10);
      final card = applyCardReview({'id': 'c1', 'q': 'x', 'a': 'y', 'interval': 0}, 4, now);
      expect(card['interval'], 1);
      expect(card['q'], 'x');
      expect(DateTime.parse(card['dueAt'] as String), now.add(const Duration(days: 1)));
      expect(card['reviewHistory'], [
        {
          'quality': 4,
          'reviewedAt': now.toIso8601String(),
          'interval': 1,
          'ease': 2.5,
          'reps': 1,
          'lapses': 0,
        },
      ]);
    });

    test('cards without a due date or with a past due date are due', () {
      final now = DateTime(2026, 11, 18, 10);
      expect(isCardDue({}, now), isTrue);
      expect(isCardDue({'dueAt': now.add(const Duration(days: 1)).toIso8601String()}, now), isFalse);
      expect(isCardDue({'dueAt': now.subtract(const Duration(hours: 1)).toIso8601String()}, now), isTrue);
    });
  });

  group('adaptive planner', () {
    test('respects the daily cap and spreads work over days', () {
      final plan = buildAdaptivePlan(
        tasks: [task('a', minutes: 60), task('b', minutes: 60), task('c', minutes: 60)],
        exams: const [],
        deadlines: const [],
        today: today,
        dailyMinutes: 120,
      );
      expect(plan.assignments.length, 3);
      expect(plan.unplacedIds, isEmpty);
      for (final minutes in plan.loadByDay.values) {
        expect(minutes, lessThanOrEqualTo(120));
      }
      expect(plan.loadByDay.values.fold<int>(0, (sum, value) => sum + value), 180);
    });

    test('never schedules work on rest weekdays', () {
      final friday = DateTime(2026, 11, 20);
      final plan = buildAdaptivePlan(
        tasks: [task('a')],
        exams: const [],
        deadlines: const [],
        today: friday,
        restWeekdays: {DateTime.friday},
      );
      expect(plan.assignments['a'], '2026-11-21');
    });

    test('overdue tasks move forward and the change is explained', () {
      final plan = buildAdaptivePlan(
        tasks: [task('old', due: '2026-11-10')],
        exams: const [],
        deadlines: const [],
        today: today,
      );
      expect(plan.assignments['old'], '2026-11-18');
      expect(plan.changes.single.newDate, '2026-11-18');
      expect(plan.changes.single.reason, contains('از موعد گذشته'));
    });

    test('weaker subjects are scheduled before stronger ones', () {
      final plan = buildAdaptivePlan(
        tasks: [
          task('strong', subject: 'ادبیات', minutes: 120),
          task('weak', subject: 'ریاضی', minutes: 120),
        ],
        exams: [
          {'id': 'e1', 'subject': 'ادبیات', 'score': 19, 'max': 20},
          {'id': 'e2', 'subject': 'ریاضی', 'score': 8, 'max': 20},
        ],
        deadlines: const [],
        today: today,
        dailyMinutes: 120,
      );
      expect(plan.assignments['weak'], '2026-11-18');
      expect(plan.assignments['strong'], '2026-11-19');
    });

    test('a near exam raises the priority of its subject', () {
      final plan = buildAdaptivePlan(
        tasks: [
          task('strong', subject: 'ادبیات', minutes: 120),
          task('weak', subject: 'ریاضی', minutes: 120),
        ],
        exams: [
          {'id': 'e1', 'subject': 'ادبیات', 'score': 19, 'max': 20},
          {'id': 'e2', 'subject': 'ریاضی', 'score': 8, 'max': 20},
        ],
        deadlines: [
          {'id': 'd1', 'subject': 'ادبیات', 'date': '2026-11-19'},
        ],
        today: today,
        dailyMinutes: 120,
      );
      expect(plan.assignments['strong'], '2026-11-18');
    });

    test('tasks longer than the daily cap are reported, not squeezed in', () {
      final plan = buildAdaptivePlan(
        tasks: [task('huge', minutes: 200)],
        exams: const [],
        deadlines: const [],
        today: today,
        dailyMinutes: 120,
      );
      expect(plan.assignments, isEmpty);
      expect(plan.unplacedIds, ['huge']);
    });

    test('completed tasks are not rescheduled', () {
      final plan = buildAdaptivePlan(
        tasks: [task('done', done: true)],
        exams: const [],
        deadlines: const [],
        today: today,
      );
      expect(plan.assignments, isEmpty);
      expect(plan.changes, isEmpty);
    });
  });

  group('analytics', () {
    final now = DateTime(2026, 11, 18, 12);

    test('subject averages and trend use valid scored exams only', () {
      final report = buildLearningReport(
        exams: [
          {'subject': 'ریاضی', 'score': 10, 'max': 20, 'createdAt': '2026-10-01T00:00:00.000'},
          {'subject': 'ریاضی', 'score': 16, 'max': 20, 'createdAt': '2026-11-01T00:00:00.000'},
          {'subject': 'فیزیک', 'score': 25, 'max': 20, 'createdAt': '2026-11-02T00:00:00.000'},
          {'subject': 'ادبیات', 'score': 19, 'max': 20},
        ],
        tasks: const [],
        cards: const [],
        now: now,
      );
      final math = report.subjects.firstWhere((s) => s.subject == 'ریاضی');
      expect(math.average, closeTo(65, 0.001));
      expect(math.trend, closeTo(30, 0.001));
      expect(report.subjects.any((s) => s.subject == 'فیزیک'), isFalse);
      expect(report.strengths.map((s) => s.subject), ['ادبیات']);
      expect(report.weaknesses, isEmpty);
    });

    test('adherence counts only past-due tasks and weekly minutes use completion date', () {
      final tasks = <Map<String, dynamic>>[
        {
          'id': '1',
          'minutes': 30,
          'done': true,
          'dueDate': '2026-11-15',
          'completedAt': DateTime(2026, 11, 15, 20).toUtc().toIso8601String(),
        },
        {'id': '2', 'minutes': 30, 'done': false, 'dueDate': '2026-11-16'},
        {'id': '3', 'minutes': 30, 'done': false, 'dueDate': '2026-11-18'},
        {'id': '4', 'minutes': 30, 'done': true},
      ];
      final report = buildLearningReport(exams: const [], tasks: tasks, cards: const [], now: now);
      expect(report.adherenceSample, 2);
      expect(report.adherence, 0.5);
      expect(report.weeks.length, 4);
      expect(report.weeks.last.completedMinutes, 30);
    });

    test('missing data is reported as a gap instead of an invented trend', () {
      final report = buildLearningReport(
        exams: [
          {'subject': 'ریاضی', 'score': 15, 'max': 20},
        ],
        tasks: const [],
        cards: const [],
        now: now,
      );
      expect(report.dataGaps, isNotEmpty);
      expect(report.subjects.single.trend, isNull);
      expect(report.adherence, isNull);
    });

    test('counts due flashcards', () {
      final report = buildLearningReport(
        exams: const [],
        tasks: const [],
        cards: [
          {'id': 'a', 'dueAt': '2026-11-01T00:00:00'},
          {'id': 'b', 'dueAt': '2026-12-01T00:00:00'},
        ],
        now: now,
      );
      expect(report.dueCards, 1);
    });
  });

  group('daily suggestions', () {
    test('lists overdue work, weak subjects and near deadlines without guarantees', () {
      final now = DateTime(2026, 11, 18, 9);
      final tasks = <Map<String, dynamic>>[
        {'id': 'o', 'title': 'تمرین', 'subject': 'فیزیک', 'minutes': 200, 'done': false, 'dueDate': '2026-11-10'},
      ];
      final report = buildLearningReport(
        exams: [
          {'subject': 'فیزیک', 'score': 8, 'max': 20, 'createdAt': '2026-11-01T00:00:00'},
        ],
        tasks: tasks,
        cards: const [],
        now: now,
      );
      final tips = dailySuggestions(
        report: report,
        tasks: tasks,
        deadlines: [
          {'id': 'd', 'subject': 'فیزیک', 'date': '2026-11-19'},
        ],
        now: now,
      );
      expect(tips.length, lessThanOrEqualTo(3));
      expect(tips.any((tip) => tip.contains('عقب‌افتاده')), isTrue);
      expect(tips.any((tip) => tip.contains('امتحان فیزیک')), isTrue);
      for (final tip in tips) {
        expect(tip.contains('قطعی'), isFalse);
        expect(tip.contains('تضمین'), isFalse);
      }
    });

    test('falls back to one small, actionable step when there is nothing else', () {
      final report = buildLearningReport(exams: const [], tasks: const [], cards: const [], now: DateTime(2026, 11, 18));
      final tips = dailySuggestions(report: report, tasks: const [], deadlines: const [], now: DateTime(2026, 11, 18));
      expect(tips.length, 1);
      expect(tips.single, contains('یک کار کوچک'));
    });
  });

  group('persian digits', () {
    test('converts digits and leaves other characters alone', () {
      expect(toPersianDigits('2026-11-18'), '۲۰۲۶-۱۱-۱۸');
    });
  });

  group('workspace backup format', () {
    test('round-trips study sections', () {
      final raw = WorkspaceBackup.encode(
        {
          'edu.tasks': [
            {'id': 't1', 'title': 'x', 'done': false},
          ],
          'edu.profile': {'grade': 'دهم'},
        },
        DateTime(2026, 11, 18),
      );
      final decoded = WorkspaceBackup.decode(raw);
      expect(decoded.keys, containsAll(['edu.tasks', 'edu.profile']));
    });

    test('rejects the AI wallet so credits can never be created by importing a file', () {
      final raw = jsonEncode({
        'app': 'simorgh',
        'format': 1,
        'data': {
          'edu.ai.wallet': {'credits': 999999},
        },
      });
      expect(() => WorkspaceBackup.decode(raw), throwsA(isA<BackupFormatException>()));
    });

    test('rejects unknown sections, other apps and unsupported formats', () {
      expect(
        () => WorkspaceBackup.decode(jsonEncode({'app': 'simorgh', 'format': 1, 'data': <String, Object?>{'edu.unknown': <Object>[]}})),
        throwsA(isA<BackupFormatException>()),
      );
      expect(
        () => WorkspaceBackup.decode(jsonEncode({'app': 'other', 'format': 1, 'data': <String, Object?>{}})),
        throwsA(isA<BackupFormatException>()),
      );
      expect(
        () => WorkspaceBackup.decode(jsonEncode({'app': 'simorgh', 'format': 9, 'data': {}})),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('rejects malformed JSON, empty input and wrong item shapes', () {
      expect(() => WorkspaceBackup.decode('not json'), throwsA(isA<BackupFormatException>()));
      expect(() => WorkspaceBackup.decode('   '), throwsA(isA<BackupFormatException>()));
      expect(
        () => WorkspaceBackup.decode(jsonEncode({'app': 'simorgh', 'format': 1, 'data': {'edu.tasks': 'bad'}})),
        throwsA(isA<BackupFormatException>()),
      );
      expect(
        () => WorkspaceBackup.decode(jsonEncode({'app': 'simorgh', 'format': 1, 'data': {'edu.tasks': [1, 2]}})),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('rejects oversized input before parsing it', () {
      final huge = 'x' * (WorkspaceBackup.maxBytes + 1);
      expect(() => WorkspaceBackup.decode(huge), throwsA(isA<BackupFormatException>()));
    });
  });
}
