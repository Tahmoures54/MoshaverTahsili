import 'package:flutter_test/flutter_test.dart';
import 'package:moshaver_tahsili/education/education_store.dart';
import 'support/memory_secure_local_cipher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:moshaver_tahsili/education/ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EducationStore.secureCipherOverride = MemorySecureLocalCipher();
  });

  test('new wallet receives five welcome credits once and charges one per successful answer', () async {
    final store = await EducationStore.open();
    expect(store.credits, 5);
    expect(store.feathers, 5);
    expect(EducationStore.questionFeatherCost, 1);
    expect(store.freeAiUsesRemaining, 0);
    final welcome = store.creditHistory.single;
    expect(welcome['kind'], 'bonus');
    expect(welcome['amount'], 5);
    final untouchedReopen = await EducationStore.open(preferences: store.prefs);
    expect(untouchedReopen.credits, 5);
    expect(untouchedReopen.creditHistory.where((entry) => entry['kind'] == 'bonus'), hasLength(1));

    final reservation = await store.prepareAiRequest(id: 'first', question: 'پرسش اول');
    expect(reservation.usesFreeUse, isFalse);
    expect(store.credits, 4);
    expect(store.feathers, 4);
    await store.completeAiRequest('first', 'پاسخ معتبر');
    await store.refundAiRequest('first');
    expect(store.credits, 4);
    final reopened = await EducationStore.open(preferences: store.prefs);
    expect(reopened.credits, 4);
    expect(reopened.creditHistory.where((entry) => entry['kind'] == 'bonus'), hasLength(1));
  });

  test('a failed question returns its reserved feather exactly once', () async {
    final store = await EducationStore.open();
    final reservation = await store.prepareAiRequest(id: 'failed-question', question: 'پرسش ناموفق');
    expect(reservation.usesFreeUse, isFalse);
    expect(store.feathers, 4);
    expect(store.creditHistory.first['title'], 'فراخوان سیمرغ · یک پر');
    await store.refundAiRequest('failed-question');
    await store.refundAiRequest('failed-question');
    expect(store.feathers, 5);
    expect(store.creditHistory.where((item) => item['kind'] == 'refund'), hasLength(1));
    expect(store.creditHistory.first['title'], 'بازگشت یک پر سیمرغ · درخواست ناموفق');
  });

  test('malformed structured teaching feedback refunds the completed request once', () async {
    final store = await EducationStore.open();
    await store.prepareAiRequest(id: 'bad-structured-turn', question: 'پرسش درس');
    await store.completeAiRequest('bad-structured-turn', 'not valid teaching JSON');
    expect(store.feathers, 4);
    await store.refundInvalidAiResponse('bad-structured-turn');
    await store.refundInvalidAiResponse('bad-structured-turn');
    expect(store.feathers, 5);
    expect(store.savedAiAnswer('bad-structured-turn'), isNull);
    expect(store.creditHistory.where((item) => item['kind'] == 'refund'), hasLength(1));
    final retry = await store.prepareAiRequest(id: 'bad-structured-turn', question: 'پرسش درس');
    expect(retry.isCompleted, isFalse);
    expect(store.feathers, 4);
  });

  test('existing Bazaar product identifiers and feather amounts stay compatible', () {
    expect(CreditCatalog.products.map((product) => product.id), ['credit_10', 'credit_35', 'credit_90']);
    expect(CreditCatalog.products.map((product) => product.feathers), [100, 265, 550]);
  });

  testWidgets('wallet summary presents the balance as Simorgh feathers', (tester) async {
    final store = await EducationStore.open();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: CreditSummary(store: store))));
    expect(find.text('پرهای سیمرغ'), findsOneWidget);
    expect(find.text('۵ پر'), findsOneWidget);
    expect(find.text('هر پرسش جدید: یک پر · پاسخ ناموفق: بدون هزینه'), findsOneWidget);
  });

  test('legacy wallets keep their exact balance and do not receive a retroactive welcome grant', () async {
    SharedPreferences.setMockInitialValues({
      EducationStore.walletKey: '{"version":2,"credits":7,"successful_uses":2}',
    });
    final store = await EducationStore.open();
    expect(store.credits, 7);
    expect(store.creditHistory.where((entry) => entry['kind'] == 'bonus'), isEmpty);
  });
}
