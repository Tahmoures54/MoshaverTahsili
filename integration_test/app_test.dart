import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:moshaver_tahsili/education/education_store.dart';
import 'package:moshaver_tahsili/education_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Run on a disposable Android device/emulator. This uses the REAL platform
/// SharedPreferences implementation, not the unit-test mock. Clear app data
/// before running; the test intentionally clears this app's local data.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('local profile, planner, exam and advisor persist on device', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await tester.pumpWidget(const EducationApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    // The consent card and start button can extend below the viewport on
    // the emulator's 411x914 screen. Scroll the actual control into view
    // before tapping; a tap at an off-screen coordinate silently misses.
    await tester.ensureVisible(find.text('بزن بریم'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('بزن بریم'));
    await tester.pumpAndSettle();
    final fullNameField = find.byType(TextFormField).first;
    await tester.ensureVisible(fullNameField);
    await tester.pumpAndSettle();
    await tester.enterText(fullNameField, 'دانش‌آموز آزمون');
    await tester.ensureVisible(find.text('ذخیره پروفایل'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ذخیره پروفایل'));
    await tester.pumpAndSettle();
    expect(find.text('درود، دانش‌آموز آزمون!'), findsOneWidget);
    final encryptedProfile = prefs.getString('edu.profile')!;
    expect(encryptedProfile, startsWith(EducationStore.encryptedPrefix));
    expect(encryptedProfile, isNot(contains('دانش‌آموز آزمون')));

    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('افزودن برنامه'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'مرور ریاضی');
    await tester.enterText(find.byType(TextFormField).at(2), '۳۰');
    await tester.tap(find.text('افزودن'));
    await tester.pumpAndSettle();
    // The Android Keystore call is a real platform-channel operation. The
    // first settled frame can occur while its Future is still pending, so
    // keep pumping until the persisted task is reflected by the UI.
    await _pumpUntilFound(tester, find.text('مرور ریاضی'));
    expect(find.text('مرور ریاضی'), findsOneWidget);
    expect(prefs.getString('edu.tasks'), startsWith(EducationStore.encryptedPrefix));

    await tester.tap(find.byIcon(Icons.assessment_outlined).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ثبت نمره'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'ریاضی');
    await tester.enterText(find.byType(TextFormField).at(1), '۱۷');
    await tester.tap(find.widgetWithText(FilledButton, 'ثبت نمره'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pumpAndSettle();
    expect(find.text('تهیه پر'), findsOneWidget);
    await tester.tap(find.text('تهیه پر'));
    await tester.pumpAndSettle();
    expect(find.text('کیسه پرهای سیمرغ'), findsOneWidget);
    expect(find.text('بسته‌های پر سیمرغ'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // Reopen the platform-backed store in a second instance to verify that
    // profile, planner and exam data were persisted outside the widget tree.
    final store = await EducationStore.open();
    expect(store.profile?['year'], 'هفتم');
    expect(store.tasks.single['title'], 'مرور ریاضی');
    expect(prefs.getString('edu.tasks'), startsWith(EducationStore.encryptedPrefix));
    final encryptedWallet = prefs.getString(EducationStore.walletKey);
    expect(encryptedWallet, startsWith(EducationStore.encryptedPrefix));
    expect(encryptedWallet, isNot(contains('"credits"')));
    expect(store.exams.single['score'], 17);
    expect(store.credits, 5);
    expect(store.freeAiUsesRemaining, 0);
    expect(
      store.creditHistory.any((entry) => entry['id'] == 'welcome-credits-v1'),
      isTrue,
    );
    await tester.pumpAndSettle();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
Future<void> _pumpUntilFound(WidgetTester tester, Finder finder, {
  int maxPumps = 40,
}) async {
  for (var attempt = 0; attempt < maxPumps; attempt++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
}
