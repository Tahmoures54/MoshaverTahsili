import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moshaver_tahsili/education/education_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('stores profile, tasks, exams and flashcards locally', () async {
    final store = await EducationStore.open();
    await store.saveProfile({'grade': 'متوسطه دوم', 'year': 'دهم', 'field': 'ریاضی', 'nickname': 'آزمون'});
    await store.addTask({'id': 'task-1', 'title': 'حل تمرین', 'subject': 'ریاضی', 'minutes': 45, 'done': false});
    await store.addExam({'id': 'exam-1', 'subject': 'فیزیک', 'score': 17, 'max': 20});
    await store.addCard({'id': 'card-1', 'q': 'شتاب چیست؟', 'a': 'نرخ تغییر سرعت', 'interval': 0});
    final reopened = EducationStore(store.prefs);
    expect(reopened.profile?['year'], 'دهم');
    expect(reopened.tasks.single['title'], 'حل تمرین');
    expect(reopened.exams.single['score'], 17);
    expect(reopened.cards.single['q'], 'شتاب چیست؟');
    await store.toggleTask('task-1');
    expect(store.tasks.single['done'], isTrue);
  });

  test('concurrent local additions do not overwrite one another', () async {
    final store = await EducationStore.open();
    await Future.wait([store.addTask({'id': 'a'}), store.addTask({'id': 'b'})]);
    expect(store.tasks.map((task) => task['id']), containsAll(['a', 'b']));
  });

  test('keeps the newest 80 advisor messages', () async {
    final store = await EducationStore.open();
    await store.saveMessages(List.generate(85, (i) => {'role': 'user', 'content': 'message-$i'}));
    expect(store.messages, hasLength(80));
    expect(store.messages.first['content'], 'message-5');
    expect(store.messages.last['content'], 'message-84');
  });

  test('credits a valid pack once, including concurrent duplicate delivery', () async {
    final store = await EducationStore.open();
    final results = await Future.wait(List.generate(2, (_) => store.grantProduct(
        productId: 'credit_10', purchaseToken: 'token-1', creditsToAdd: 10)));
    expect(results.where((value) => value), hasLength(1));
    expect(store.credits, 10);
    expect(store.creditHistory, hasLength(1));
    expect(EducationStore(store.prefs).credits, 10);
  });

  test('rejects guessed products, mismatched amounts and empty tokens', () async {
    final store = await EducationStore.open();
    await expectLater(store.grantProduct(productId: 'guessed', purchaseToken: 't', creditsToAdd: 10), throwsA(isA<LocalDataException>()));
    await expectLater(store.grantProduct(productId: 'credit_10', purchaseToken: 't', creditsToAdd: 999), throwsA(isA<LocalDataException>()));
    await expectLater(store.grantProduct(productId: 'credit_10', purchaseToken: '', creditsToAdd: 10), throwsA(isA<LocalDataException>()));
    expect(store.credits, 0);
    expect(store.creditHistory, isEmpty);
  });

  test('two successful free uses then one credit per success; never negative', () async {
    final store = await EducationStore.open();
    expect(store.freeAiUsesRemaining, 2);
    expect(await store.recordSuccessfulAiUse(requestId: 'f1'), isTrue);
    expect(await store.recordSuccessfulAiUse(requestId: 'f2'), isTrue);
    expect(await store.recordSuccessfulAiUse(requestId: 'f3'), isFalse);
    expect(store.credits, 0);
    expect(store.canUseAi, isFalse);
    await store.grantProduct(productId: 'credit_10', purchaseToken: 't2', creditsToAdd: 10);
    expect(await store.recordSuccessfulAiUse(requestId: 'paid'), isTrue);
    expect(await store.recordSuccessfulAiUse(requestId: 'paid'), isFalse);
    expect(store.credits, 9);
  });

  test('concurrent reservations cannot overdraw a single credit', () async {
    SharedPreferences.setMockInitialValues({EducationStore.walletKey: jsonEncode({'credits': 1, 'successful_uses': 2})});
    final store = await EducationStore.open();
    final results = await Future.wait([
      store.prepareAiRequest(id: 'a', question: 'first').then<Object>((value) => value).catchError((Object error) => error),
      store.prepareAiRequest(id: 'b', question: 'second').then<Object>((value) => value).catchError((Object error) => error),
    ]);
    expect(results.whereType<AiReservation>(), hasLength(1));
    expect(results.whereType<LocalDataException>(), hasLength(1));
    expect(store.credits, 0);
    await store.refundAiRequest('a');
    await store.refundAiRequest('b');
    await store.refundAiRequest('a');
    expect(store.credits, 1);
  });

  test('completion and refund are idempotent and survive reopening', () async {
    SharedPreferences.setMockInitialValues({EducationStore.walletKey: jsonEncode({'credits': 2, 'successful_uses': 2})});
    final store = await EducationStore.open();
    await store.prepareAiRequest(id: 'a', question: 'question');
    await store.completeAiRequest('a', 'saved answer');
    await store.completeAiRequest('a', 'saved answer');
    await store.refundAiRequest('a');
    expect(store.credits, 1);
    final reopened = await EducationStore.open();
    expect(reopened.savedAiAnswer('a'), 'saved answer');
    final retry = await reopened.prepareAiRequest(id: 'a', question: 'question');
    expect(retry.cachedAnswer, 'saved answer');
    expect(reopened.credits, 1);
    await expectLater(reopened.prepareAiRequest(id: 'a', question: 'different'), throwsA(isA<LocalDataException>()));
  });

  test('startup refunds interrupted paid and free reservations exactly once', () async {
    SharedPreferences.setMockInitialValues({EducationStore.walletKey: jsonEncode({
      'version': 2, 'credits': 0, 'successful_uses': 2, 'purchase_tokens': <String, dynamic>{}, 'transactions': <Map<String, dynamic>>[],
      'requests': {'interrupted': {'question': 'q', 'status': 'pending', 'charge': 'credit', 'createdAt': '2026-01-01T00:00:00Z'}},
    })});
    final store = await EducationStore.open();
    expect(store.credits, 1);
    expect(store.freeAiUsesRemaining, 0);
    await store.refundInterruptedRequests();
    expect((await EducationStore.open()).credits, 1);
    expect(store.creditHistory.where((item) => item['kind'] == 'refund'), hasLength(1));
  });

  test('startup refunds every interrupted paid reservation, not just one', () async {
    SharedPreferences.setMockInitialValues({EducationStore.walletKey: jsonEncode({
      'version': 2, 'credits': 0, 'successful_uses': 2,
      'purchase_tokens': <String, dynamic>{}, 'transactions': <Map<String, dynamic>>[],
      'requests': {
        'interrupted-a': {'question': 'q1', 'status': 'pending', 'charge': 'credit', 'createdAt': '2026-01-01T00:00:00Z'},
        'interrupted-b': {'question': 'q2', 'status': 'pending', 'charge': 'credit', 'createdAt': '2026-01-01T00:00:01Z'},
        'interrupted-c': {'question': 'q3', 'status': 'pending', 'charge': 'free', 'createdAt': '2026-01-01T00:00:02Z'},
      },
    })});
    final store = await EducationStore.open();
    expect(store.credits, 2);
    expect(store.freeAiUsesRemaining, 2);
    expect(store.creditHistory.where((item) => item['kind'] == 'refund'), hasLength(2));
    await store.refundInterruptedRequests();
    final reopened = await EducationStore.open();
    expect(reopened.credits, 2);
    expect(reopened.freeAiUsesRemaining, 2);
    expect(reopened.creditHistory.where((item) => item['kind'] == 'refund'), hasLength(2));
  });

  test('damaged wallet fails closed and is never silently reset', () async {
    SharedPreferences.setMockInitialValues({EducationStore.walletKey: '{broken'});
    final store = await EducationStore.open();
    expect(store.walletError, isNotNull);
    expect(store.canUseAi, isFalse);
    await expectLater(store.grantProduct(productId: 'credit_10', purchaseToken: 't', creditsToAdd: 10), throwsA(isA<LocalDataException>()));
    expect(store.prefs.getString(EducationStore.walletKey), '{broken');
  });

  test('migrates v1 token ledger without losing balance or duplicate protection', () async {
    SharedPreferences.setMockInitialValues({EducationStore.walletKey: jsonEncode({'credits': 7, 'successful_uses': 3, 'purchase_tokens': ['old-token']})});
    final store = await EducationStore.open();
    expect(store.credits, 7);
    expect(store.freeAiUsesRemaining, 0);
    expect(await store.grantProduct(productId: 'credit_10', purchaseToken: 'old-token', creditsToAdd: 10), isFalse);
    expect(store.credits, 7);
  });

  test('workspace reset preserves wallet and financial history', () async {
    final store = await EducationStore.open();
    await store.grantProduct(productId: 'credit_10', purchaseToken: 't', creditsToAdd: 10);
    await store.recordSuccessfulAiUse();
    await store.saveProfile({'grade': 'ابتدایی'});
    await store.addTask({'id': 'task'});
    await store.saveMessages([{'role': 'user', 'content': 'سلام'}]);
    await store.addReport({'id': 'report', 'answer': 'پاسخ'});
    await store.clear();
    expect(store.profile, isNull);
    expect(store.tasks, isEmpty);
    expect(store.messages, isEmpty);
    expect(store.reports, isEmpty);
    expect(store.credits, 10);
    expect(store.freeAiUsesRemaining, 1);
    expect(store.creditHistory, hasLength(2));
  });

  test('damaged workspace lists are preserved instead of overwritten', () async {
    SharedPreferences.setMockInitialValues({'edu.tasks': '{broken'});
    final store = await EducationStore.open();
    expect(store.tasks, isEmpty);
    expect(store.dataError('edu.tasks'), isNotNull);
    await expectLater(store.addTask({'id': 'new'}), throwsA(isA<LocalDataException>()));
    expect(store.prefs.getString('edu.tasks'), '{broken');
  });
}
