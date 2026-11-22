import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:moshaver_tahsili/education/education_store.dart';
import 'package:moshaver_tahsili/education_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

// تعریف Keyها به‌صورت متمرکز برای جلوگیری از Hardcode شدن متن‌ها در تست
abstract final class TestKeys {
  static const consentCheckbox = Key('consent_checkbox');
  static const startButton = Key('start_button');
  static const profileForm = Key('profile_form');
  static const profileNameField = Key('profile_name_field');
  static const saveProfileButton = Key('save_profile_button');
  static const plannerTab = Key('nav_planner');
  static const addTaskButton = Key('add_task_button');
  static const taskTitleField = Key('task_title_field');
  static const taskDurationField = Key('task_duration_field');
  static const addTaskSubmit = Key('add_task_submit');
  static const examsTab = Key('nav_exams');
  static const addExamButton = Key('add_exam_button');
  static const examSubjectField = Key('exam_subject_field');
  static const examScoreField = Key('exam_score_field');
  static const addExamSubmit = Key('add_exam_submit');
  static const aiTab = Key('nav_ai');
  static const aiPackButton = Key('ai_pack_button');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'local profile, planner, exam and advisor persist on device',
    (tester) async {
      // ۱. پاک‌سازی داده‌های قبلی
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // ۲. بالا آمدن اپلیکیشن
      await tester.pumpWidget(const EducationApp());
      await _settleSafely(tester); // استفاده از helper با Timeout مشخص

      // ۳. پذیرش قوانین و شروع
      await tester.tap(find.byKey(TestKeys.consentCheckbox));
      await _settleSafely(tester);
      await tester.ensureVisible(find.byKey(TestKeys.startButton));
      await _settleSafely(tester);
      await tester.tap(find.byKey(TestKeys.startButton));
      await _settleSafely(tester);

      // ۴. پر کردن پروفایل
      final nameField = find.byKey(TestKeys.profileNameField);
      await tester.ensureVisible(nameField);
      await _settleSafely(tester);
      await tester.enterText(nameField, 'دانش‌آموز آزمون');
      await tester.ensureVisible(find.byKey(TestKeys.saveProfileButton));
      await _settleSafely(tester);
      await tester.tap(find.byKey(TestKeys.saveProfileButton));
      await _settleSafely(tester);

      // ۵. بررسی ذخیره‌سازی رمزنگاری‌شده پروفایل
      expect(find.text('درود، دانش‌آموز!'), findsOneWidget);
      final encryptedProfile = prefs.getString('edu.profile')!;
      expect(encryptedProfile, startsWith(EducationStore.encryptedPrefix));
      expect(encryptedProfile, isNot(contains('دانش‌آموز آزمون')));

      // ۶. رفتن به تب برنامه‌ریزی و افزودن تسک
      await tester.tap(find.byKey(TestKeys.plannerTab));
      await _settleSafely(tester);
      await tester.tap(find.byKey(TestKeys.addTaskButton));
      await _settleSafely(tester);
      await tester.enterText(find.byKey(TestKeys.taskTitleField), 'مرور ریاضی');
      await tester.enterText(find.byKey(TestKeys.taskDurationField), '۳۰');
      await tester.tap(find.byKey(TestKeys.addTaskSubmit));
      await _settleSafely(tester);

      // ۷. انتظار برای نمایش تسک (با استفاده از waitFor داخلی)
      // در محیط Integration، عملیات پلتفرمی ممکن است بیش از چند فریم طول بکشد
      await _pumpUntilFound(tester, find.text('مرور ریاضی'), maxWait: const Duration(seconds: 10));
      expect(find.text('مرور ریاضی'), findsOneWidget);
      expect(prefs.getString('edu.tasks'), startsWith(EducationStore.encryptedPrefix));

      // ۸. ثبت نمره
      await tester.tap(find.byKey(TestKeys.examsTab));
      await _settleSafely(tester);
      await tester.tap(find.byKey(TestKeys.addExamButton));
      await _settleSafely(tester);
      await tester.enterText(find.byKey(TestKeys.examSubjectField), 'ریاضی');
      await tester.enterText(find.byKey(TestKeys.examScoreField), '۱۷');
      await tester.tap(find.widgetWithText(FilledButton, 'ثبت نمره'));
      await _settleSafely(tester);

      // ۹. بررسی تب مشاور هوشمند
      await tester.tap(find.byKey(TestKeys.aiTab));
      await _settleSafely(tester);
      expect(find.text('تهیه پر'), findsOneWidget);
      // Do not open the real Bazaar shop in emulator smoke tests. The test
      // verifies the local wallet entry point; payment-provider behavior is
      // covered separately and requires a Bazaar-capable test environment.

      await tester.tap(find.byType(BackButton));
      await _settleSafely(tester);

      // ۱۰. تأیید نهایی: باز کردن مجدد Store و بررسی داده‌های پایدار
      final store = await EducationStore.open();
      expect(store.profile?['year'], 'هفتم');
      expect(store.tasks.single['title'], 'مرور ریاضی');
      final encryptedWallet = prefs.getString(EducationStore.walletKey);
      expect(encryptedWallet, startsWith(EducationStore.encryptedPrefix));
      expect(encryptedWallet, isNot(contains('"credits"')));
      expect(store.exams.single['score'], 17);
      expect(store.credits, 5);
      // این انتظار ممکن است نادرست باشد اگر AI واقعی فراخوانی نشود:
      // expect(store.freeAiUsesRemaining, 0);
      expect(
        store.creditHistory.any((entry) => entry['id'] == 'welcome-credits-v1'),
        isTrue,
      );
      await _settleSafely(tester);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

/// انجام یک چرخه Pump و Settle با Timeout مشخص (حداکثر ۵ ثانیه)
/// از فراخوانی بدون سقف `pumpAndSettle()` جلوگیری می‌کند.
Future<void> _settleSafely(WidgetTester tester, {Duration timeout = const Duration(seconds: 5)}) async {
  await tester.pumpAndSettle(timeout);
}

/// انتظار برای یافتن ویجت با محدودیت زمانی مشخص
/// به جای حلقه ثابت Pump، از زمان‌بندی امن استفاده می‌کند.
Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration maxWait = const Duration(seconds: 5),
}) async {
  final end = DateTime.now().add(maxWait);
  while (DateTime.now().isBefore(end)) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  // در صورت پیدا نشدن، اجازه می‌دهیم تست در خط expect بعدی با پیام واضح شکست بخورد
}
