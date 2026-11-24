import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moshaver_tahsili/education/backup_page.dart';
import 'package:moshaver_tahsili/education/education_store.dart';
import 'support/memory_secure_local_cipher.dart';
import 'package:moshaver_tahsili/education/learning_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('ir.moshaver.tahsili/backup');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EducationStore.secureCipherOverride = MemorySecureLocalCipher();
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  testWidgets(
    'exports the local study workspace through the Android file channel',
    (tester) async {
      final store = await EducationStore.open();
      await store.addTask({
        'id': 'task-1',
        'title': 'مرور ریاضی',
        'subject': 'ریاضی',
        'minutes': 30,
        'done': false,
      });

      String? exported;
      channel.setMockMethodCallHandler((call) async {
        expect(call.method, 'saveBackup');
        final arguments = call.arguments as Map<Object?, Object?>;
        expect(arguments['fileName'], startsWith('simorgh-backup-'));
        exported = arguments['content'] as String;
        return true;
      });

      await tester.pumpWidget(MaterialApp(home: BackupPage(store: store)));
      await tester.tap(find.text('ذخیره فایل پشتیبان'));
      await tester.pumpAndSettle();

      expect(exported, isNotNull);
      final decoded = WorkspaceBackup.decode(exported!);
      final tasks = decoded['edu.tasks'] as List<Object?>;
      expect((tasks.single as Map<Object?, Object?>)['title'], 'مرور ریاضی');
      expect(exported, isNot(contains('edu.ai.wallet')));
      expect(find.text('فایل پشتیبان ذخیره شد.'), findsOneWidget);
    },
  );

  testWidgets('loads a selected backup file into the confirmation form', (
    tester,
  ) async {
    final store = await EducationStore.open();
    final backup = WorkspaceBackup.encode({
      'edu.tasks': [
        {
          'id': 'task-2',
          'title': 'تمرین فیزیک',
          'subject': 'فیزیک',
          'minutes': 20,
          'done': false,
        },
      ],
    }, DateTime(2026, 11, 18));

    channel.setMockMethodCallHandler((call) async {
      expect(call.method, 'openBackup');
      return backup;
    });

    await tester.pumpWidget(MaterialApp(home: BackupPage(store: store)));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    await tester.tap(find.text('انتخاب و بررسی فایل پشتیبان'));
    await tester.pumpAndSettle();

    expect(
      find.text('فایل پشتیبان خوانده شد؛ برای تأیید و بازیابی اقدام کن.'),
      findsOneWidget,
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, backup);
  });
  test('exports and restores active Simorgh teaching sessions', () async {
    final source = await EducationStore.open();
    final session = {
      'id': 'lesson-backup-1',
      'active': true,
      'topic': 'کسرها',
      'grade': 'هفتم',
      'stage': 'guidedPractice',
      'diagnosticCount': 2,
      'diagnosticCorrect': 1,
      'practiceAttempts': 1,
      'masteryCount': 0,
      'masteryCorrect': 0,
      'reteachCount': 0,
      'explanationVariant': 0,
    };
    await source.saveTeachingSessions([session]);

    final raw = await source.exportBackup();
    final decoded = WorkspaceBackup.decode(raw);
    expect(decoded['edu.teaching.sessions'], [session]);
    expect(raw, isNot(contains('edu.ai.wallet')));

    SharedPreferences.setMockInitialValues({});
    final target = await EducationStore.open();
    await target.importBackup(raw);
    expect(target.teachingSessions, [session]);
  });
}
