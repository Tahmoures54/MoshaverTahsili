import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moshaver_tahsili/education/simorgh_companion.dart';
import 'package:moshaver_tahsili/education/ui.dart';

void main() {
  final now = DateTime(2026, 11, 18, 10);

  group('buildSimorghGuidance', () {
    test('welcomes a student who has not created a study item', () {
      final result = buildSimorghGuidance(tasks: [], cards: [], now: now);

      expect(result.mood, SimorghMood.welcome);
      expect(result.action, SimorghAction.planner);
      expect(result.message, contains('یک هدف کوچک'));
    });

    test('prioritizes overdue tasks and suggests rescheduling without blame', () {
      final result = buildSimorghGuidance(
        tasks: [
          {'id': 'late', 'done': false, 'dueDate': '2026-11-17'},
          {'id': 'today', 'done': false, 'dueDate': '2026-11-18'},
        ],
        cards: [
          {'id': 'due-card', 'dueAt': '2026-11-18T08:00:00'},
        ],
        now: now,
      );

      expect(result.mood, SimorghMood.gentle);
      expect(result.action, SimorghAction.planner);
      expect(result.title, contains('یک‌جا'));
      expect(result.message, contains('۱ کار'));
    });

    test('recommends review when flashcards are due', () {
      final result = buildSimorghGuidance(
        tasks: [],
        cards: [
          {'id': 'due', 'dueAt': '2026-11-18T09:00:00'},
          {'id': 'future', 'dueAt': '2026-11-20T09:00:00'},
        ],
        now: now,
      );

      expect(result.mood, SimorghMood.thinking);
      expect(result.action, SimorghAction.review);
      expect(result.message, contains('۱ فلش‌کارت'));
    });

    test('celebrates a task completed today using completedAt', () {
      final result = buildSimorghGuidance(
        tasks: [
          {
            'id': 'done-today',
            'done': true,
            'completedAt': '2026-11-18T09:15:00',
          },
          {
            'id': 'done-old',
            'done': true,
            'completedAt': '2026-11-10T09:15:00',
          },
        ],
        cards: [],
        now: now,
      );

      expect(result.mood, SimorghMood.celebrating);
      expect(result.action, SimorghAction.planner);
      expect(result.message, contains('۱ کار'));
    });

    test('uses pending work as a neutral next-step prompt', () {
      final result = buildSimorghGuidance(
        tasks: [
          {'id': 'one', 'done': false},
          {'id': 'two', 'done': false},
        ],
        cards: [],
        now: now,
      );

      expect(result.mood, SimorghMood.encouraging);
      expect(result.message, contains('۲ کار'));
    });
  });

  testWidgets('companion renders, animates, and routes its actions', (tester) async {
    SimorghAction? selectedAction;
    var chatOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: SimorghCompanion(
              tasks: const [],
              cards: const [],
              now: now,
              onAction: (action) => selectedAction = action,
              onChat: () => chatOpened = true,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.text('همراه تو، سیمرغ'), findsOneWidget);
    expect(find.text('سفر یادگیری از یک قدم آغاز می‌شود'), findsOneWidget);
    expect(find.byKey(const ValueKey('simorgh-character-painter')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('ساخت اولین برنامه'));
    await tester.pump();
    expect(selectedAction, SimorghAction.planner);

    await tester.tap(find.text('گفت‌وگو با مشاور'));
    await tester.pump();
    expect(chatOpened, isTrue);

    await tester.pumpWidget(
      const SizedBox(),
    );
  });

  testWidgets('companion pauses its ticker when the home tab is inactive', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SimorghCompanion(
            tasks: const [],
            cards: const [],
            active: false,
            now: now,
            onAction: (_) {},
            onChat: () {},
          ),
        ),
      ),
    );

    expect(
      tester.widget<TickerMode>(
        find.byKey(const ValueKey('simorgh-animation-ticker')),
      ).enabled,
      isFalse,
    );
    await tester.pumpWidget(
      const SizedBox(),
    );
  });

  testWidgets('companion remains usable on a compact phone width', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Directionality(
            textDirection: TextDirection.rtl,
            child: SimorghCompanion(
              tasks: const [
                {'id': 'task', 'done': false},
              ],
              cards: const [],
              now: now,
              onAction: (_) {},
              onChat: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('قدم بعدی را خودت انتخاب کن'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      const SizedBox(),
    );
  });
}
