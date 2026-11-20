import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moshaver_tahsili/education/ai_advisor_service.dart';
import 'package:moshaver_tahsili/education/assessment_pages.dart';
import 'package:moshaver_tahsili/education/analytics_page.dart';
import 'package:moshaver_tahsili/education/learning_coach_page.dart';
import 'package:moshaver_tahsili/education/study_pages.dart';
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
      expect(find.text('درود بر جوینده دانایی!'), findsOneWidget);
      expect(find.text('رد پای تلاش تو'), findsOneWidget);
      expect(find.text('پیشنهاد امروز سیمرغ'), findsOneWidget);
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
    await tester.tap(find.byTooltip('فراخواندن سیمرغ · مصرف یک پر'));
    await tester.pumpAndSettle();
    expect(store.credits, 1);
    expect(store.messages.last['status'], 'failed');
    final requestId = store.messages.last['id'].toString();
    final failedWallet = store.walletSnapshot;
    expect(failedWallet['requests'][requestId]['charge'], 'credit');
    expect(failedWallet['requests'][requestId]['status'], 'refunded');
    expect(find.text('تلاش دوباره همین درخواست'), findsNWidgets(2));
    final retryButton = find.byKey(ValueKey('advisor-retry-$requestId'));
    await tester.scrollUntilVisible(
      find.text('تلاش دوباره همین درخواست').last,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(retryButton, findsOneWidget);
    expect(tester.widget<TextButton>(retryButton).onPressed, isNotNull);
    tester.widget<TextButton>(retryButton).onPressed!.call();
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
    expect(store.messages.last['status'], 'completed', reason: 'AI turn failed: ${store.messages.last['content']}');
    expect(store.messages.where((message) => message['role'] == 'user'), hasLength(2));
    expect(store.messages.first['id'], 'previous-failed');
    expect(store.messages.first['status'], 'failed');
    expect(store.messages.last['content'], contains('Recovered after retry'));
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });

  testWidgets('Simorgh teaching evaluates a student answer and persists lesson progress', (tester) async {
    final store = await EducationStore.open();
    await store.saveProfile({
      'grade': 'پایه محرمانه',
      'year': 'یازدهم',
      'aiProfileContextConsent': false,
    });
    var teachingProviderCalls = 0;
    String? teachingPrompt;
    final service = AiAdvisorService(
      store: store,
      apiKey: 'test-key',
      client: MockClient((request) async {
        teachingProviderCalls++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final messages = body['messages'] as List;
        teachingPrompt = messages.first['content']?.toString();
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
          headers: {'content-type': 'application/json; charset=utf-8'},
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
    expect(find.textContaining('روش تدریس سیمرغ'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'یک دوم');
    final sendButton = find.ancestor(
      of: find.byTooltip('فراخواندن سیمرغ · مصرف یک پر'),
      matching: find.byType(IconButton),
    );
    tester.widget<IconButton>(sendButton).onPressed!.call();
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    expect(teachingProviderCalls, 1);
    expect(teachingPrompt, contains('ساختار دقیق'));
    expect(teachingPrompt, contains('ابتدا یک پرسش کوتاه'));
    expect(teachingPrompt, contains('پایه تحصیلی مشخص نشده'));
    expect(teachingPrompt, isNot(contains('پایه محرمانه')));
    expect(teachingPrompt, isNot(contains('یازدهم')));
    expect(store.messages.last['status'], 'completed');
    expect(store.messages.last['content'], contains('آفرین؛ پاسخ تو درست بود.'));
    expect(store.teachingSessions.single['diagnosticCount'], 1);
    expect(store.teachingSessions.single['diagnosticCorrect'], 1);
    expect(find.textContaining('آفرین؛ پاسخ تو درست بود.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });


  testWidgets('Simorgh chat carries model evaluations across diagnostic, practice and reteaching stages', (tester) async {
    final store = await EducationStore.open();
    final outcomes = ['correct', 'correct', 'correct', 'partial', 'malformed'];
    final prompts = <String>[];
    var call = 0;
    final service = AiAdvisorService(
      store: store,
      apiKey: 'test-key',
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final messages = body['messages'] as List;
        prompts.add(messages.first['content'].toString());
        final outcome = outcomes[call++];
        final content = outcome == 'malformed'
            ? 'پاسخ غیرساختاریافته مدل'
            : jsonEncode({
                'feedback': 'بازخورد مرحله $call',
                'outcome': outcome,
                'error': outcome == 'partial' ? 'procedural' : 'unknown',
                'nextQuestion': 'پرسش بعدی مرحله $call',
              });
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': content},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await tester.pumpWidget(frame(AdvisorPage(store: store, service: service)));
    await tester.tap(find.byKey(const ValueKey('simorgh-start-teaching')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'کسرها');
    await tester.tap(find.widgetWithText(FilledButton, 'شروع ارزیابی'));
    await tester.pumpAndSettle();

    Future<void> answer(String value) async {
      await tester.enterText(find.byType(TextField).last, value);
      final sendButton = find.ancestor(
        of: find.byTooltip('فراخواندن سیمرغ · مصرف یک پر'),
        matching: find.byType(IconButton),
      );
      tester.widget<IconButton>(sendButton).onPressed!.call();
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await answer('پاسخ تشخیصی اول');
    expect(store.teachingSessions.single['stage'], 'diagnostic');
    await answer('پاسخ تشخیصی دوم');
    expect(store.teachingSessions.single['stage'], 'diagnostic');
    await answer('پاسخ تشخیصی سوم');
    expect(store.teachingSessions.single['stage'], 'guidedPractice');
    expect(store.messages.last['content'], contains('بازخورد مرحله 3'));
    expect(store.messages.last['content'], contains('مرحله بعدی آموزش آماده است'));
    await answer('تمرین نیمه‌درست');
    expect(store.teachingSessions.single['stage'], 'reteach');
    expect(store.teachingSessions.single['lastError'], 'procedural');
    await answer('پاسخ بازآموزی');

    // A malformed provider payload is visible as a safe retry message and
    // cannot change the deterministic lesson state or its counters.
    expect(store.teachingSessions.single['stage'], 'reteach');
    expect(store.teachingSessions.single['practiceAttempts'], 1);
    expect(store.teachingSessions.single['reteachCount'], 1);
    expect(store.messages.last['content'], contains('پاسخ آموزشی ساختار معتبری نداشت'));

    expect(call, 5);
    expect(prompts[0], contains('ابتدا یک پرسش کوتاه'));
    expect(prompts[1], contains('ابتدا یک پرسش کوتاه'));
    expect(prompts[2], contains('ابتدا یک پرسش کوتاه'));
    expect(prompts[3], contains('روش سقراطی'));
    expect(prompts[4], contains('روش توضیح متفاوت'));
    expect(prompts[0], contains('calculation یعنی خطای محاسبات عددی'));
    expect(prompts[0], contains('شواهد پاسخ'));
    expect(prompts[0], contains('partial وقتی'));
    final assistantMessages = store.messages
        .where((message) => message['role'] == 'assistant')
        .toList();
    expect(assistantMessages, hasLength(5));
    expect(assistantMessages[3]['content'], contains('بازخورد مرحله 4'));
    expect(store.teachingSessions.single['diagnosticCount'], 3);
    expect(store.teachingSessions.single['diagnosticCorrect'], 3);
    expect(store.teachingSessions.single['practiceAttempts'], 1);
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
    await tester.scrollUntilVisible(find.text('تاریخچه پرها'), 300);
    await tester.pumpAndSettle();
    expect(find.text('تاریخچه پرها'), findsOneWidget);
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
  testWidgets('ConsultationRunner does not dispose an injected shared AI service', (tester) async {
    final store = await EducationStore.open();
    final sharedClient = _TrackingHttpClient();
    final sharedService = AiAdvisorService(
      apiKey: 'test-key',
      client: sharedClient,
    );

    await tester.pumpWidget(frame(ConsultationRunner(
      store: store,
      service: sharedService,
      kind: 'academic',
      title: 'آزمون مالکیت سرویس',
      question: 'یک پرسش آزمایشی',
      autoStart: false,
    )));
    await tester.pumpWidget(frame(const SizedBox.shrink()));
    expect(sharedClient.closed, isFalse);

    final answer = await tester.runAsync(
      () => sharedService.ask(
        profile: null,
        history: const [],
        question: 'سرویس هنوز فعال است؟',
      ),
    );
    expect(answer, 'پاسخ آزمایشی');
    expect(sharedClient.calls, 1);
    sharedService.dispose();
    expect(sharedClient.closed, isFalse);
    sharedClient.close();
  });


testWidgets('analytics tolerates malformed legacy teaching counters', (tester) async {
    final store = await EducationStore.open();
    await store.saveTeachingSessions([
      {
        'id': 'legacy-lesson',
        'active': false,
        'topic': 'درس قدیمی',
        'stage': 'unknown',
        'diagnosticCount': 'نامعتبر',
        'masteryCorrect': 1.5,
      },
    ]);
    await tester.pumpWidget(frame(AnalyticsPage(store: store)));
    await tester.scrollUntilVisible(
      find.text('درس قدیمی'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('درس قدیمی'), findsOneWidget);
    expect(find.textContaining('۰ ارزیابی آغازین'), findsOneWidget);
    expect(find.textContaining('۱ پاسخ درست در سنجش پایانی'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('planner tolerates malformed legacy task durations', (tester) async {
    final store = await EducationStore.open();
    await store.addTask({
      'id': 'legacy-task',
      'title': 'کار قدیمی',
      'minutes': 'نامعتبر',
      'done': false,
    });
    await tester.pumpWidget(frame(PlannerPage(store: store, changed: () {})));
    await tester.pumpAndSettle();
    expect(find.text('کار قدیمی'), findsOneWidget);
    expect(find.textContaining('۰ دقیقه مطالعه برنامه‌ریزی کرده‌ای'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('learning coach handles malformed legacy task durations', () {
    final plan = buildLearningCoachPlan(
      exams: const [],
      tasks: [
        {
          'id': 'legacy-overdue',
          'title': 'کار عقب‌افتاده',
          'minutes': 'نامعتبر',
          'dueDate': '2026-11-18',
          'done': false,
        },
        {
          'id': 'legacy-overdue-2',
          'title': 'کار دوم',
          'minutes': 15,
          'dueDate': '2026-11-18',
          'done': false,
        },
      ],
      cards: const [],
      deadlines: const [],
      now: DateTime(2026, 11, 19),
    );
    expect(plan.steps, isNotEmpty);
    expect(plan.steps.first.kind, 'overdue');
  });

}

class _TrackingHttpClient extends http.BaseClient {
  bool closed = false;
  int calls = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (closed) throw StateError('shared client was closed');
    calls++;
    final body = jsonEncode({
      'choices': [
        {'message': {'content': 'پاسخ آزمایشی'}},
      ],
    });
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }

  @override
  void close() {
    closed = true;
  }
}
