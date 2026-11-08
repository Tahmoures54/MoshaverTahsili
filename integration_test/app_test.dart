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
  testWidgets('local profile, planner, exam and advisor survive an app restart', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await tester.pumpWidget(const EducationApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('بزن بریم'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'دانش‌آموز آزمون');
    await tester.ensureVisible(find.text('ذخیره پروفایل'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ذخیره پروفایل'));
    await tester.pumpAndSettle();
    expect(find.text('سلام دانش‌آموز آزمون!'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.calendar_month_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('افزودن برنامه'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'مرور ریاضی');
    await tester.enterText(find.byType(TextFormField).at(2), '۳۰');
    await tester.tap(find.text('افزودن'));
    await tester.pumpAndSettle();
    expect(find.text('مرور ریاضی'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.assessment_outlined).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ثبت نمره'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'ریاضی');
    await tester.enterText(find.byType(TextFormField).at(1), '۱۷');
    await tester.tap(find.text('ثبت نمره'));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.auto_awesome_outlined));
    await tester.pumpAndSettle();
    expect(find.text('خرید اعتبار'), findsOneWidget);
    await tester.tap(find.text('خرید اعتبار'));
    await tester.pumpAndSettle();
    expect(find.text('کیف اعتبار و خرید'), findsOneWidget);
    expect(find.text('بازیابی خریدها'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    // Recreate the widget tree and reopen the platform-backed store.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const EducationApp());
    await tester.pumpAndSettle();
    final store = await EducationStore.open();
    expect(store.profile?['year'], 'هفتم');
    expect(store.tasks.single['title'], 'مرور ریاضی');
    expect(store.exams.single['score'], 17);
    expect(store.credits, 0);
    expect(store.freeAiUsesRemaining, 2);
    await tester.pumpAndSettle();
  });
}
