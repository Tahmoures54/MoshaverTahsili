import 'package:flutter_test/flutter_test.dart';
import 'package:moshaver_tahsili/education/education_store.dart';
import 'support/memory_secure_local_cipher.dart';
import 'package:moshaver_tahsili/education/learning_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EducationStore.secureCipherOverride = MemorySecureLocalCipher();
  });

  test('export leaves out the AI wallet and import restores the study workspace', () async {
    final store = await EducationStore.open();
    await store.addTask({'id': 't1', 'title': 'مرور فصل', 'subject': 'ریاضی', 'minutes': 30, 'done': false});
    await store.addDeadline({'id': 'd1', 'subject': 'فیزیک', 'date': '2026-12-01'});

    final raw = await store.exportBackup();
    expect(raw.contains('edu.ai.wallet'), isFalse);

    await store.clear();
    expect(store.tasks, isEmpty);
    expect(store.deadlines, isEmpty);

    final sections = await store.importBackup(raw);
    expect(sections, greaterThan(0));
    expect(store.tasks.single['title'], 'مرور فصل');
    expect(store.deadlines.single['subject'], 'فیزیک');
  });

  test('a rejected backup leaves existing data untouched', () async {
    final store = await EducationStore.open();
    await store.addTask({'id': 'keep', 'title': 'کار اصلی', 'subject': 'ریاضی', 'minutes': 20, 'done': false});

    await expectLater(
      store.importBackup('{"app":"simorgh","format":1,"data":{"edu.tasks":"bad"}}'),
      throwsA(isA<BackupFormatException>()),
    );
    expect(store.tasks.single['title'], 'کار اصلی');
  });

  test('applyPlanDates stores planner dates on the matching tasks only', () async {
    final store = await EducationStore.open();
    await store.addTask({
      'id': 'a', 'title': 'الف', 'subject': 'ریاضی', 'minutes': 20,
      'done': false, 'dueDate': '2026-11-10',
    });
    await store.addTask({'id': 'b', 'title': 'ب', 'subject': 'ریاضی', 'minutes': 20, 'done': false});

    await store.applyPlanDates(
      {'a': '2026-11-18'},
      changes: const [
        PlanChange(
          taskId: 'a',
          title: 'الف',
          newDate: '2026-11-18',
          reason: 'به‌دلیل عقب‌افتادگی جابه‌جا شد.',
        ),
      ],
      now: DateTime(2026, 11, 18, 12),
    );

    final byId = {for (final task in store.tasks) task['id']: task};
    expect(byId['a']!['dueDate'], '2026-11-18');
    final history = byId['a']!['planHistory'] as List;
    expect(history.single['previousDate'], '2026-11-10');
    expect(history.single['newDate'], '2026-11-18');
    expect(history.single['reason'], contains('عقب‌افتادگی'));
    expect(byId['b']!.containsKey('dueDate'), isFalse);
  });

  test('reviewCard applies SM-2 to the stored card', () async {
    final store = await EducationStore.open();
    await store.addCard({'id': 'c1', 'q': 'شتاب چیست؟', 'a': 'تغییر سرعت', 'interval': 0});

    final now = DateTime(2026, 11, 18, 10);
    await store.reviewCard('c1', 4, now);

    final card = store.cards.single;
    expect(card['interval'], 1);
    expect(card['reps'], 1);
    expect(isCardDue(card, now), isFalse);
  });
}
