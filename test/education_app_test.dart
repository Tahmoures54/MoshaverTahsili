import 'dart:async';
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
  setUp(() => SharedPreferences.setMockInitialValues({}));

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
    final retryResponse = Completer<http.Response>();
    final service = AiAdvisorService(store: store, apiKey: 'test-key', client: MockClient((_) async {
      calls++;
      if (calls == 1) return http.Response('unavailable', 503);
      return retryResponse.future;
    }));
    await tester.pumpWidget(frame(AdvisorPage(store: store, service: service)));
    await tester.enterText(find.byType(TextField), 'چطور بهتر مطالعه کنم؟');
    await tester.tap(find.byTooltip('ارسال پرسش'));
    await tester.pumpAndSettle();
    expect(store.credits, 1);
    expect(store.messages.last['status'], 'failed');
    final requestId = store.messages.last['id'].toString();
    final failedWallet = jsonDecode((await SharedPreferences.getInstance())
        .getString(EducationStore.walletKey)!);
    expect(failedWallet['requests'][requestId]['charge'], 'credit');
    expect(failedWallet['requests'][requestId]['status'], 'refunded');
    expect(find.text('تلاش دوباره همین درخواست'), findsNWidgets(2));
    final retryButton = find.byKey(ValueKey('advisor-retry-$requestId'));
    expect(retryButton, findsOneWidget);
    expect(tester.widget<TextButton>(retryButton).onPressed, isNotNull);
    await tester.scrollUntilVisible(retryButton, 300, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(retryButton);
    await tester.pump();
    expect(calls, 2);
    retryResponse.complete(http.Response(
        jsonEncode({'choices': [{'message': {'content': 'Recovered after retry'}}]}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'}));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(calls, 2);
    final completedWallet = jsonDecode((await SharedPreferences.getInstance())
        .getString(EducationStore.walletKey)!);
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

  testWidgets('shop shows balance, packages, purchase result and history', (tester) async {
    final store = await EducationStore.open();
    final gateway = FakeGateway();
    final billing = BazaarBillingService(store, gateway: gateway,
        publicKey: 'test-key', catalogConfirmed: true, supportedPlatform: true);
    await tester.pumpWidget(MaterialApp(locale: const Locale('fa'),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: CreditShopPage(store: store, billing: billing)));
    await tester.pumpAndSettle();
    expect(find.text('بسته برنزی'), findsOneWidget);
    await tester.tap(find.text('خرید از بازار').first);
    await tester.pumpAndSettle();
    expect(store.credits, 10);
    await tester.scrollUntilVisible(find.text('تاریخچه اعتبار'), 300);
    await tester.pumpAndSettle();
    expect(find.text('تاریخچه اعتبار'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('بسته برنزی').last, 300);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline study guide contains practical methods', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: StudyTipsPage()));
    await tester.pumpAndSettle();
    expect(find.text('روش‌های مؤثر مطالعه'), findsOneWidget);
    expect(find.text('مطالعه فعال'), findsOneWidget);
    expect(find.text('مرور فاصله‌دار'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('آمادگی برای امتحان'), 350, scrollable: find.byType(Scrollable).first);
    expect(find.text('آمادگی برای امتحان'), findsOneWidget);
  });
}
