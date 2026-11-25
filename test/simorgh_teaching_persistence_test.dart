import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moshaver_tahsili/education/advisor_page.dart';
import 'package:moshaver_tahsili/education/education_store.dart';
import 'support/memory_secure_local_cipher.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EducationStore.secureCipherOverride = MemorySecureLocalCipher();
  });

  test('persists and restores an active teaching session', () async {
    final store = await EducationStore.open();
    await store.saveTeachingSessions([
      {
        'id': 'simorgh-teaching-archived',
        'active': false,
        'topic': 'کسرها',
        'grade': 'هفتم',
        'stage': 'completed',
        'diagnosticCount': 3,
        'diagnosticCorrect': 1,
        'practiceAttempts': 2,
        'masteryCount': 3,
        'masteryCorrect': 2,
        'reteachCount': 1,
        'explanationVariant': 2,
        'lastError': 'procedural',
      },
      {
        'id': 'simorgh-teaching-active',
        'active': true,
        'topic': 'معادله درجه دوم',
        'grade': 'متوسطه دوم · دهم',
        'stage': 'masteryCheck',
        'diagnosticCount': 3,
        'diagnosticCorrect': 1,
        'practiceAttempts': 2,
        'masteryCount': 1,
        'masteryCorrect': 1,
        'reteachCount': 1,
        'explanationVariant': 2,
        'lastError': null,
      },
    ]);

    final reopened = await EducationStore.open(preferences: store.prefs);
    expect(reopened.teachingSessions, hasLength(2));
    final active = reopened.teachingSessions.last;
    expect(active['id'], 'simorgh-teaching-active');
    expect(active['topic'], 'معادله درجه دوم');
    expect(active['grade'], 'متوسطه دوم · دهم');
    expect(active['stage'], 'masteryCheck');
    expect(active['diagnosticCount'], 3);
    expect(active['diagnosticCorrect'], 1);
    expect(active['practiceAttempts'], 2);
    expect(active['masteryCount'], 1);
    expect(active['masteryCorrect'], 1);
    expect(active['reteachCount'], 1);
    expect(active['explanationVariant'], 2);
    expect(active['active'], isTrue);
    expect(reopened.teachingSessions.first['active'], isFalse);
    expect(reopened.teachingSessions.first['stage'], 'completed');
  });
  testWidgets(
    'advisor recovers a completed AI answer when transcript write was interrupted',
    (tester) async {
      final store = await EducationStore.open();
      await store.prepareAiRequest(
        id: 'recovery-request',
        question: 'پرسش ذخیره‌شده',
      );
      await store.completeAiRequest(
        'recovery-request',
        'پاسخ بازیابی‌شده از دفتر امن',
      );

      await store.saveMessages([
        {
          'id': 'recovery-request',
          'role': 'user',
          'content': 'پرسش ذخیره‌شده',
          'status': 'pending',
          'createdAt': '2026-11-20T10:00:00.000Z',
        },
      ]);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AdvisorPage(store: store)),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        store.messages.singleWhere((item) => item['role'] == 'user')['status'],
        'completed',
      );
      expect(find.text('پاسخ بازیابی‌شده از دفتر امن'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'advisor restores the exact lesson stage and can prepare its next step',
    (tester) async {
      final store = await EducationStore.open();
      await store.saveTeachingSessions([
        {
          'id': 'simorgh-resume-check',
          'active': true,
          'topic': 'معادله درجه دوم',
          'grade': 'متوسطه دوم · دهم',
          'stage': 'masteryCheck',
          'diagnosticCount': 3,
          'diagnosticCorrect': 1,
          'practiceAttempts': 2,
          'masteryCount': 1,
          'masteryCorrect': 1,
          'reteachCount': 1,
          'explanationVariant': 2,
          'lastError': null,
        },
      ]);

      final reopened = await EducationStore.open(preferences: store.prefs);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AdvisorPage(store: reopened)),
        ),
      );
      expect(find.text('روش تدریس سیمرغ · سنجش یادگیری'), findsOneWidget);
      expect(find.text('جلسه: معادله درجه دوم'), findsOneWidget);

      await tester.ensureVisible(find.text('آماده‌سازی گام آموزشی'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('آماده‌سازی گام آموزشی'));
      await tester.pump();
      final input = tester.widget<TextField>(find.byType(TextField));
      expect(input.controller!.text, contains('معادله درجه دوم'));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('does not resume a corrupted lesson with impossible counters', (
    tester,
  ) async {
    final store = await EducationStore.open();
    await store.saveTeachingSessions([
      {
        'id': 'simorgh-corrupted',
        'active': true,
        'topic': 'هندسه',
        'grade': 'هشتم',
        'stage': 'masteryCheck',
        'diagnosticCount': 3,
        'diagnosticCorrect': 4,
        'practiceAttempts': 1,
        'masteryCount': 1,
        'masteryCorrect': 1,
      },
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AdvisorPage(store: store)),
      ),
    );
    expect(find.textContaining('روش تدریس سیمرغ'), findsNothing);
    expect(tester.takeException(), isNull);
    // Corrupt data is ignored for resumption, not silently overwritten.
    expect(store.teachingSessions.single['diagnosticCorrect'], 4);
  });
}
