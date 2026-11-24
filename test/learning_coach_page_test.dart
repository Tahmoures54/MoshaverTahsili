import 'package:flutter_test/flutter_test.dart';
import 'package:moshaver_tahsili/education/learning_coach_page.dart';

void main() {
  final now = DateTime(2026, 11, 18, 10);

  test(
    'prioritizes an exam within three days and offers an actionable review',
    () {
      final plan = buildLearningCoachPlan(
        exams: const [],
        tasks: const [],
        cards: const [],
        deadlines: [
          {'subject': 'زیست', 'date': '2026-11-20'},
        ],
        now: now,
      );
      expect(plan.steps.first.kind, 'deadline');
      expect(plan.steps.first.subject, 'زیست');
      expect(plan.steps.first.minutes, 20);
    },
  );

  test(
    'uses repeated low exam evidence for targeted practice, not one score',
    () {
      final plan = buildLearningCoachPlan(
        exams: [
          {'subject': 'ریاضی', 'score': 8, 'max': 20},
          {'subject': 'ریاضی', 'score': 9, 'max': 20},
        ],
        tasks: const [],
        cards: const [],
        deadlines: const [],
        now: now,
      );
      expect(plan.steps.any((step) => step.kind == 'practice'), isTrue);
      expect(
        plan.steps.firstWhere((step) => step.kind == 'practice').subject,
        'ریاضی',
      );
    },
  );

  test('does not label a subject weak from a single low score', () {
    final plan = buildLearningCoachPlan(
      exams: [
        {'subject': 'فیزیک', 'score': 2, 'max': 20},
      ],
      tasks: const [],
      cards: const [],
      deadlines: const [],
      now: now,
    );
    expect(plan.steps.any((step) => step.kind == 'practice'), isFalse);
    expect(plan.evidenceNotes, isNotEmpty);
  });

  test('suggests due flashcards and an overdue task in small steps', () {
    final plan = buildLearningCoachPlan(
      exams: const [],
      tasks: [
        {
          'id': 'old',
          'title': 'تمرین فصل دو',
          'subject': 'شیمی',
          'minutes': 60,
          'done': false,
          'dueDate': '2026-11-16',
        },
      ],
      cards: [
        {'id': 'card', 'dueAt': '2026-11-17T10:00:00'},
      ],
      deadlines: const [],
      now: now,
    );
    expect(plan.steps.any((step) => step.kind == 'overdue'), isTrue);
    expect(plan.steps.any((step) => step.kind == 'retrieval'), isTrue);
    expect(plan.steps.length, lessThanOrEqualTo(3));
  });

  test('respects the daily time budget and avoids duplicate open tasks', () {
    final plan = buildLearningCoachPlan(
      exams: const [],
      tasks: [
        {
          'id': 'today',
          'title': 'برنامه قبلی',
          'minutes': 55,
          'done': false,
          'dueDate': '2026-11-18',
        },
        {
          'id': 'same',
          'title': 'یک نوبت یادآوری فعال',
          'minutes': 0,
          'done': false,
          'dueDate': '2026-11-18',
        },
      ],
      cards: const [],
      deadlines: const [],
      now: now,
      dailyMinutes: 60,
    );
    expect(plan.availableMinutes, 5);
    expect(plan.steps, isEmpty);
  });

  test('combined recommendations never exceed the remaining daily budget', () {
    final plan = buildLearningCoachPlan(
      exams: [
        {'subject': 'ریاضی', 'score': 4, 'max': 20},
        {'subject': 'ریاضی', 'score': 5, 'max': 20},
      ],
      tasks: [
        {
          'id': 'today',
          'title': 'برنامه قبلی',
          'minutes': 90,
          'done': false,
          'dueDate': '2026-11-18',
        },
        {
          'id': 'old',
          'title': 'کار عقب‌افتاده',
          'subject': 'فیزیک',
          'minutes': 60,
          'done': false,
          'dueDate': '2026-11-16',
        },
      ],
      cards: [
        {'id': 'card', 'dueAt': '2026-11-17T10:00:00'},
      ],
      deadlines: [
        {'subject': 'زیست', 'date': '2026-11-19'},
      ],
      now: now,
      dailyMinutes: 120,
    );

    expect(plan.availableMinutes, 30);
    expect(plan.steps.map((step) => step.kind), ['deadline', 'retrieval']);
    expect(
      plan.steps.fold<int>(0, (sum, step) => sum + step.minutes),
      lessThanOrEqualTo(plan.availableMinutes),
    );
  });

  test('ignores malformed exam scores and safely handles empty workspaces', () {
    final plan = buildLearningCoachPlan(
      exams: [
        {'subject': 'ریاضی', 'score': 'bad', 'max': 20},
      ],
      tasks: const [],
      cards: const [],
      deadlines: const [],
      now: now,
    );
    expect(plan.steps.single.kind, 'starter');
    expect(plan.evidenceNotes, isNotEmpty);
  });
}
