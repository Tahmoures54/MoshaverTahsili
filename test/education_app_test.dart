import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moshaver_tahsili/education/ai_advisor_service.dart';
import 'package:moshaver_tahsili/education/bazaar_billing_service.dart';
import 'package:moshaver_tahsili/education/credit_shop_page.dart';
import 'package:moshaver_tahsili/education/education_store.dart';
import 'support/memory_secure_local_cipher.dart';
import 'package:moshaver_tahsili/education/ui.dart';
import 'package:moshaver_tahsili/education_app.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bazaar_billing_service_test.dart' show FakeGateway;

Widget frame(Widget child) => MaterialApp(locale: const Locale('fa'),
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: const [Locale('fa')], theme: buildAppTheme(),
    builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
    home: Scaffold(body: child));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EducationStore.secureCipherOverride = MemorySecureLocalCipher();
  });

  testWidgets('Persian welcome requires privacy acknowledgement before profile', (tester) async {
    await tester.pumpWidget(const EducationApp());
    await tester.pumpAndSettle();
    expect(find.text('مشاور هوشمند تحصیلی'), findsOneWidget);
    expect(find.text('سخنی با اولیا و دانش‌آموزان گرامی'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'بزن بریم')).onPressed, isNull);
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('بزن بریم'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('بزن بریم'));
    await tester.pumpAndSettle();
    expect(find.text('پایه تحصیلی'), findsOneWidget);
    await tester.ensureVisible(find.text('ذخیره پروفایل'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ذخیره پروفایل'));
    await tester.pumpAndSettle();
    expect(find.text('سلام، همراه پرتلاش!'), findsOneWidget);
    final store = await EducationStore.open();
    expect(store.profile?['grade'], 'متوسطه اول');
    expect(store.profile?['year'], 'هفتم');
  });

  testWidgets('editing profile preserves unrelated existing settings', (tester) async {
    final store = await EducationStore.open();
    await store.saveProfile({
      'nickname': 'دانش‌آموز', 'grade': 'متوسطه اول', 'year': 'هفتم',
      'field': 'عمومی', 'goal': 'پیشرفت', 'dailyMinutes': 90,
      'aiContextConsent': true, 'customPreference': 'keep-me',
    });
    await tester.pumpWidget(frame(Builder(builder: (context) => Center(child: ElevatedButton(
      onPressed: () => showProfileSheet(context, store), child: const Text('ویرایش'),
    )))));
    await tester.tap(find.text('ویرایش'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ذخیره پروفایل'));
    await tester.pumpAndSettle();
    expect(store.profile?['dailyMinutes'], 90);
    expect(store.profile?['aiContextConsent'], isTrue);
    expect(store.profile?['customPreference'], 'keep-me');
  });

  testWidgets('AI profile context consent is opt-in and can be revoked', (tester) async {
    final store = await EducationStore.open();
    await store.saveProfile({'grade': 'متوسطه اول', 'year': 'هفتم', 'field': 'عمومی'});
    await tester.pumpWidget(frame(Builder(builder: (context) => Center(child: ElevatedButton(
      onPressed: () => showProfileSheet(context, store),
      child: const Text('ویرایش پروفایل'),
    )))));

    await tester.tap(find.text('ویرایش پروفایل'));
    await tester.pumpAndSettle();
    final consentLabel = find.text('اجازه ارسال زمینه تحصیلی به هوش مصنوعی');
    await tester.ensureVisible(consentLabel);
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(find.ancestor(
      of: consentLabel, matching: find.byType(CheckboxListTile),
    )).value, isFalse);
    await tester.tap(consentLabel);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ذخیره پروفایل'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ذخیره پروفایل'));
    await tester.pumpAndSettle();
    expect(store.profile?['aiProfileContextConsent'], isTrue);

    await tester.tap(find.text('ویرایش پروفایل'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(consentLabel);
    await tester.pumpAndSettle();
    await tester.tap(consentLabel);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ذخیره پروفایل'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ذخیره پروفایل'));
    await tester.pumpAndSettle();
    expect(store.profile?['aiProfileContextConsent'], isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home weekly progress uses completion date rather than creation date', (tester) async {
    final store = await EducationStore.open();
    final now = DateTime.now();
    await store.addTask({
      'id': 'completed-recently',
      'title': 'مرور فصل اول',
      'subject': 'ریاضی',
      'minutes': 35,
      'done': true,
      'createdAt': now.subtract(const Duration(days: 20)).toIso8601String(),
      'completedAt': now.subtract(const Duration(days: 2)).toIso8601String(),
    });
    await store.addTask({
      'id': 'completed-long-ago',
      'title': 'تمرین قدیمی',
      'subject': 'فیزیک',
      'minutes': 50,
      'done': true,
      'createdAt': now.subtract(const Duration(days: 20)).toIso8601String(),
      'completedAt': now.subtract(const Duration(days: 12)).toIso8601String(),
    });
    await tester.pumpWidget(frame(HomePage(store: store, go: (_) {})));
    expect(find.textContaining('هفت روز اخیر: ۱ کار تکمیل شده؛ ۳۵ دقیقه'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adaptive planner previews changes and requires confirmation', (tester) async {
    final store = await EducationStore.open();
    await store.addTask({'id': 'overdue', 'title': 'تمرین جبر', 'subject': 'ریاضی',
      'minutes': 30, 'done': false, 'dueDate': '2020-01-01'});
    await tester.pumpWidget(frame(PlannerPage(store: store, changed: () {})));
    await tester.tap(find.text('ساخت برنامه هوشمند'));
    await tester.pumpAndSettle();
    expect(store.tasks.single['dueDate'], '2020-01-01');
    expect(find.text('اعمال برنامه'), findsOneWidget);
    await tester.tap(find.text('فعلاً نه'));
    await tester.pumpAndSettle();
    expect(store.tasks.single['dueDate'], '2020-01-01');

    await tester.tap(find.text('ساخت برنامه هوشمند'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('اعمال برنامه'));
    await tester.pumpAndSettle();
    expect(store.tasks.single['dueDate'], isNot('2020-01-01'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard fits compact and regular phones and navigates locally', (tester) async {
    for (final size in [const Size(320, 568), const Size(390, 844)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final store = await EducationStore.open();
      await store.saveProfile({'grade': 'متوسطه دوم', 'year': 'دهم', 'field': 'ریاضی'});
      await tester.pumpWidget(EducationApp(store: store));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byIcon(Icons.calendar_month_outlined));
      await tester.pumpAndSettle();
      expect(find.text('افزودن برنامه'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.assessment_outlined).last);
      await tester.pumpAndSettle();
      expect(find.text('ثبت نمره'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  });

  testWidgets('study task and exam forms validate and persist input', (tester) async {
    final store = await EducationStore.open();
    await tester.pumpWidget(frame(PlannerPage(store: store, changed: () {})));
    await tester.tap(find.text('افزودن برنامه'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('افزودن'));
    await tester.pumpAndSettle();
    expect(find.text('عنوان کار را بنویس.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).at(0), 'حل تمرین ریاضی');
    await tester.enterText(find.byType(TextFormField).at(2), '۴۵');
    await tester.tap(find.text('افزودن'));
    await tester.pumpAndSettle();
    expect(store.tasks.single['minutes'], 45);
    expect(find.text('حل تمرین ریاضی'), findsOneWidget);

    await tester.pumpWidget(frame(ExamsPage(store: store, changed: () {})));
    await tester.tap(find.text('ثبت نمره'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'ریاضی');
    await tester.enterText(find.byType(TextFormField).at(1), '۱۸');
    await tester.tap(find.widgetWithText(FilledButton, 'ثبت نمره'));
    await tester.pumpAndSettle();
    expect(store.exams.single['score'], 18);
    expect(examPercentage(store.exams.single), 90);
  });

  testWidgets('advisor keeps failed question retryable and never displays it as an AI answer', (tester) async {
    SharedPreferences.setMockInitialValues({EducationStore.walletKey: jsonEncode({
      'version': 2, 'credits': 1, 'successful_uses': 2,
      'purchase_tokens': <String, dynamic>{}, 'requests': <String, dynamic>{},
      'transactions': <Map<String, dynamic>>[],
    })});
    final store = await EducationStore.open();
    expect(store.successfulAiUses, 2);
    expect(store.freeAiUsesRemaining, 0);
    var calls = 0;
    await store.saveMessages([
      {'id': 'previous-failed', 'role': 'user', 'content': 'پرسش ناموفق قبلی',
        'status': 'failed', 'createdAt': '2026-01-01T00:00:00Z'},
    ]);
    final service = AiAdvisorService(store: store, apiKey: 'test-key',
        timeout: const Duration(seconds: 2), client: MockClient((_) async {
      calls++;
      return calls == 1 ? http.Response('unavailable', 503) : http.Response(
          jsonEncode({'choices': [{'message': {'content': 'Recovered after retry'}}]}), 200);
    }));
    await tester.pumpWidget(frame(AdvisorPage(store: store, service: service)));
    await tester.enterText(find.byType(TextField), 'چطور بهتر مطالعه کنم؟');
    await tester.tap(find.byTooltip('ارسال پرسش'));
    await tester.pumpAndSettle();
    expect(store.credits, 1);
    expect(store.messages.last['status'], 'failed');
    final requestId = store.messages.last['id'].toString();
    final failedWallet = store.walletSnapshot;
    expect(failedWallet['requests'][requestId]['charge'], 'credit');
    expect(failedWallet['requests'][requestId]['status'], 'refunded');
    expect(find.text('تلاش دوباره همین درخواست'), findsOneWidget);
    final retryButton = find.byKey(ValueKey('advisor-retry-$requestId'));
    await tester.scrollUntilVisible(
      find.text('تلاش دوباره همین درخواست').last,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(retryButton, findsOneWidget);
    expect(tester.widget<TextButton>(retryButton).onPressed, isNotNull);
    await tester.ensureVisible(retryButton);
    await tester.tap(retryButton, warnIfMissed: false);
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 3)));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(calls, 2);
    final completedWallet = store.walletSnapshot;
    expect(completedWallet['requests'][requestId]['charge'], 'credit');
    expect(completedWallet['requests'][requestId]['status'], 'completed');
    expect(completedWallet['credits'], 0);
    expect(store.credits, 0);
    expect(store.messages.last['status'], 'completed');
    expect(store.messages.where((message) => message['role'] == 'user'), hasLength(2));
    expect(store.messages.first['id'], 'previous-failed');
    expect(store.messages.first['status'], 'failed');
    expect(store.messages.last['content'], contains('Recovered after retry'));
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });

  testWidgets('Simorgh teaching evaluates a student answer and persists lesson progress', (tester) async {
    final store = await EducationStore.open();
    final service = AiAdvisorService(
      store: store,
      apiKey: 'test-key',
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final messages = body['messages'] as List;
        expect(messages.first['content'], contains('ساختار دقیق'));
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'feedback': 'آفرین؛ پاسخ تو درست بود.',
                    'outcome': 'correct',
                    'error': 'unknown',
                    'nextQuestion': 'یک مثال دیگر حل کن.',
                  }),
                },
              },
            ],
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(frame(AdvisorPage(store: store, service: service)));
    await tester.tap(find.byKey(const ValueKey('simorgh-start-teaching')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'کسرها');
    await tester.tap(find.widgetWithText(FilledButton, 'شروع ارزیابی'));
    await tester.pumpAndSettle();
    expect(store.teachingSessions.single['stage'], 'diagnostic');
    await tester.enterText(find.byType(TextField).last, 'یک دوم');
    final sendButton = find.byTooltip('ارسال پرسش');
    await tester.ensureVisible(sendButton);
    await tester.pumpAndSettle();
    await tester.tap(sendButton, warnIfMissed: false);
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    expect(store.teachingSessions.single['diagnosticCount'], 1);
    expect(store.teachingSessions.single['diagnosticCorrect'], 1);
    expect(find.textContaining('آفرین؛ پاسخ تو درست بود.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });

  testWidgets('shop shows balance, packages, purchase result and history', (tester) async {
    final store = await EducationStore.open();
    final gateway = FakeGateway();
    final billing = BazaarBillingService(store, gateway: gateway,
        publicKey: 'test-key', catalogConfirmed: true, supportedPlatform: true);
    await tester.pumpWidget(MaterialApp(locale: const Locale('fa'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: CreditShopPage(store: store, billing: billing)));
    await tester.pumpAndSettle();
    expect(find.textContaining('بسته برنزی'), findsOneWidget);
    await tester.tap(find.text('خرید از بازار').first);
    await tester.pumpAndSettle();
    expect(store.credits, 105);
    await tester.scrollUntilVisible(find.text('تاریخچه اعتبار'), 300);
    await tester.pumpAndSettle();
    expect(find.text('تاریخچه اعتبار'), findsOneWidget);
    await tester.scrollUntilVisible(find.textContaining('بسته برنزی').last, 300);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline study guide contains practical methods', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: StudyTipsPage()));
    await tester.pumpAndSettle();
    expect(find.text('روش‌های مؤثر مطالعه'), findsOneWidget);
    expect(find.text('مطالعه فعال'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('مرور فاصله‌دار'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('مرور فاصله‌دار'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('آمادگی برای امتحان'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('آمادگی برای امتحان'), findsOneWidget);
  });
}
