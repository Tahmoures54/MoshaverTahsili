import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:moshaver_tahsili/education/education_store.dart';
import 'package:moshaver_tahsili/education/learning_engine.dart';
import 'support/memory_secure_local_cipher.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EducationStore.secureCipherOverride = MemorySecureLocalCipher();
  });

  test('stores profile, tasks, exams and flashcards locally', () async {
    final store = await EducationStore.open();
    await store.saveProfile({'grade': 'متوسطه دوم', 'year': 'دهم', 'field': 'ریاضی', 'nickname': 'آزمون'});
    await store.addTask({'id': 'task-1', 'title': 'حل تمرین', 'subject': 'ریاضی', 'minutes': 45, 'done': false});
    await store.addExam({'id': 'exam-1', 'subject': 'فیزیک', 'score': 17, 'max': 20});
    await store.addCard({'id': 'card-1', 'q': 'شتاب چیست؟', 'a': 'نرخ تغییر سرعت', 'interval': 0});
    final reopened = await EducationStore.open(preferences: store.prefs);
    expect(reopened.profile?['year'], 'دهم');
    expect(reopened.tasks.single['title'], 'حل تمرین');
    expect(reopened.exams.single['score'], 17);
    expect(reopened.cards.single['q'], 'شتاب چیست؟');
    await store.toggleTask('task-1');
    expect(store.tasks.single['done'], isTrue);
  });

  test('persists optional flashcard topic and SM-2 review evidence', () async {
    final store = await EducationStore.open();
    await store.addCard({'id': 'topic-card', 'q': 'تابع چیست؟', 'a': 'رابطه ورودی و خروجی',
      'topic': 'تابع', 'interval': 0, 'ease': 2.5, 'reps': 0, 'lapses': 0});
    await store.reviewCard('topic-card', 4, DateTime(2026, 11, 18));
    final reopened = await EducationStore.open(preferences: store.prefs);
    expect(reopened.cards.single['topic'], 'تابع');
    expect(reopened.cards.single['reviewHistory'], hasLength(1));
    expect((reopened.cards.single['reviewHistory'] as List).single['quality'], 4);
  });

  test('task completion timestamp is recorded and cleared when reopened', () async {
    final store = await EducationStore.open();
    await store.addTask({'id': 'task-time', 'title': 'مرور فیزیک', 'done': false});
    await store.toggleTask('task-time');
    final completed = store.tasks.single;
    expect(completed['done'], isTrue);
    final completedAt = DateTime.tryParse(completed['completedAt']?.toString() ?? '');
    expect(completedAt, isNotNull);
    expect(completedAt!.isAfter(DateTime.now().subtract(const Duration(minutes: 1))), isTrue);

    await store.toggleTask('task-time');
    final reopened = store.tasks.single;
    expect(reopened['done'], isFalse);
    expect(reopened.containsKey('completedAt'), isFalse);
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
        productId: 'credit_10', purchaseToken: 'token-1', creditsToAdd: 100)));
    expect(results.where((value) => value), hasLength(1));
    expect(store.credits, 105);
    expect(store.creditHistory, hasLength(2));
    expect((await EducationStore.open(preferences: store.prefs)).credits, 105);
  });

  test('rejects guessed products, mismatched amounts and empty tokens', () async {
    final store = await EducationStore.open();
    await expectLater(store.grantProduct(productId: 'guessed', purchaseToken: 't', creditsToAdd: 100), throwsA(isA<LocalDataException>()));
    await expectLater(store.grantProduct(productId: 'credit_10', purchaseToken: 't', creditsToAdd: 999), throwsA(isA<LocalDataException>()));
    await expectLater(store.grantProduct(productId: 'credit_10', purchaseToken: '', creditsToAdd: 100), throwsA(isA<LocalDataException>()));
    expect(store.credits, 5);
    expect(store.creditHistory, hasLength(1));
  });

  test('new wallet receives five one-time credits; every successful answer costs one', () async {
    final store = await EducationStore.open();
    expect(store.credits, 5);
    expect(store.freeAiUsesRemaining, 0);
    expect(store.creditHistory.single['kind'], 'bonus');
    expect(await store.recordSuccessfulAiUse(requestId: 'welcome-1'), isTrue);
    expect(await store.recordSuccessfulAiUse(requestId: 'welcome-2'), isTrue);
    expect(store.credits, 3);
    final reopened = await EducationStore.open(preferences: store.prefs);
    expect(reopened.credits, 3);
    expect(reopened.creditHistory.where((entry) => entry['kind'] == 'bonus'), hasLength(1));
    expect(await reopened.recordSuccessfulAiUse(requestId: 'welcome-1'), isFalse);
    expect(reopened.credits, 3);
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
    expect(store.freeAiUsesRemaining, 0);
    expect(store.creditHistory.where((item) => item['kind'] == 'refund'), hasLength(2));
    await store.refundInterruptedRequests();
    final reopened = await EducationStore.open();
    expect(reopened.credits, 2);
    expect(reopened.freeAiUsesRemaining, 0);
    expect(reopened.creditHistory.where((item) => item['kind'] == 'refund'), hasLength(2));
  });

  test('damaged wallet fails closed and is never silently reset', () async {
    SharedPreferences.setMockInitialValues({EducationStore.walletKey: '{broken'});
    final store = await EducationStore.open();
    expect(store.walletError, isNotNull);
    expect(store.canUseAi, isFalse);
    await expectLater(store.grantProduct(productId: 'credit_10', purchaseToken: 't', creditsToAdd: 100), throwsA(isA<LocalDataException>()));
    expect(store.walletRaw, '{broken');
    expect(store.prefs.getString(EducationStore.walletKey), startsWith(EducationStore.encryptedPrefix));
  });

  test('migrates v1 token ledger without losing balance or duplicate protection', () async {
    SharedPreferences.setMockInitialValues({EducationStore.walletKey: jsonEncode({'credits': 7, 'successful_uses': 3, 'purchase_tokens': ['old-token']})});
    final store = await EducationStore.open();
    expect(store.credits, 7);
    expect(store.freeAiUsesRemaining, 0);
    expect(await store.grantProduct(productId: 'credit_10', purchaseToken: 'old-token', creditsToAdd: 100), isFalse);
    expect(store.credits, 7);
  });

  test('wallet size limit counts UTF-8 bytes and preserves oversized stored data', () async {
    final tokens = <String, dynamic>{};
    for (var index = 0; index < 4100; index++) {
      final id = index.toString().padLeft(12, '0') + ('م' * 500);
      tokens[id] = {'productId': 'credit_10', 'credits': 10};
    }
    final raw = jsonEncode({
      'version': 2,
      'credits': 10,
      'successful_uses': 2,
      'purchase_tokens': tokens,
      'requests': <String, dynamic>{},
      'transactions': <Map<String, dynamic>>[],
    });
    expect(raw.length, lessThan(EducationStore.maxWalletBytes));
    expect(utf8.encode(raw).length, greaterThan(EducationStore.maxWalletBytes));
    SharedPreferences.setMockInitialValues({EducationStore.walletKey: raw});
    final store = await EducationStore.open();
    expect(store.walletError, isNotNull);
    expect(store.canUseAi, isFalse);
    expect(store.walletRaw, raw);
    expect(store.prefs.getString(EducationStore.walletKey), startsWith(EducationStore.encryptedPrefix));
  });

  test('startup refunds pending requests and trims old entries to the stored request cap', () async {
    final requests = <String, dynamic>{
      for (var index = 0; index < EducationStore.maxStoredRequests + 1; index++)
        'pending-$index': {
          'question': 'question $index',
          'status': 'pending',
          'charge': 'credit',
          'createdAt': '2026-01-01T00:00:00Z',
        },
    };
    final raw = jsonEncode({
      'version': 2,
      'credits': 1000,
      'successful_uses': 2,
      'purchase_tokens': <String, dynamic>{},
      'requests': requests,
      'transactions': <Map<String, dynamic>>[],
    });
    SharedPreferences.setMockInitialValues({EducationStore.walletKey: raw});
    final store = await EducationStore.open(preferences: await SharedPreferences.getInstance());
    expect(store.credits, 1101);
    final reservation = await store.prepareAiRequest(id: 'new-request', question: 'new question');
    expect(reservation.usesFreeUse, isFalse);
    expect(store.credits, 1100);
    final saved = store.walletSnapshot;
    final savedRequests = saved['requests'] as Map;
    expect(savedRequests.length, EducationStore.maxStoredRequests);
    expect(savedRequests.containsKey('new-request'), isTrue);
    expect(savedRequests.values.every((entry) => entry['status'] == 'refunded' || entry['status'] == 'pending'), isTrue);
  });

  test('workspace reset preserves wallet and financial history', () async {
    final store = await EducationStore.open();
    await store.grantProduct(productId: 'credit_10', purchaseToken: 't', creditsToAdd: 100);
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
    expect(store.credits, 104);
    expect(store.freeAiUsesRemaining, 0);
    expect(store.creditHistory, hasLength(3));
  });

  test('failed workspace reset restores the original encrypted sections', () async {
    final initial = await EducationStore.open();
    await initial.saveProfile({'nickname': 'پروفایل قبلی'});
    await initial.addTask({'id': 'old-task', 'title': 'کار قبلی'});
    final prefs = initial.prefs;
    final originalProfile = prefs.getString('edu.profile');
    final originalTasks = prefs.getString('edu.tasks');
    final store = await EducationStore.open(
      preferences: prefs,
      removePreference: (key) async {
        if (key == 'edu.tasks') return false;
        return prefs.remove(key);
      },
    );

    await expectLater(store.clear(), throwsA(isA<LocalDataException>()));
    expect(prefs.getString('edu.profile'), originalProfile);
    expect(prefs.getString('edu.tasks'), originalTasks);
    expect(store.profile?['nickname'], 'پروفایل قبلی');
    expect(store.tasks.single['id'], 'old-task');
    expect(store.dataError('edu.profile'), isNull);
    expect(store.dataError('edu.tasks'), isNull);
  });

  test('damaged workspace lists are preserved instead of overwritten', () async {
    SharedPreferences.setMockInitialValues({'edu.tasks': '{broken'});
    final store = await EducationStore.open();
    expect(store.tasks, isEmpty);
    expect(store.dataError('edu.tasks'), isNotNull);
    await expectLater(store.addTask({'id': 'new'}), throwsA(isA<LocalDataException>()));
    expect(store.prefs.getString('edu.tasks'), startsWith(EducationStore.encryptedPrefix));
  });
  test('failed backup import preserves the exact ciphertext of a damaged section', () async {
    final damagedCiphertext = 'enc:v2:damaged-original-envelope';
    SharedPreferences.setMockInitialValues({
      'edu.profile': jsonEncode({'nickname': 'قدیمی'}),
      'edu.tasks': damagedCiphertext,
    });
    final cipher = _FailingTasksCipher();
    final store = await EducationStore.open(cipher: cipher);
    expect(store.dataError('edu.tasks'), isNotNull);
    final beforeProfile = store.prefs.getString('edu.profile');

    final backup = WorkspaceBackup.encode({
      'edu.profile': {'nickname': 'جدید'},
      'edu.tasks': [{'id': 'new-task', 'title': 'درس تازه'}],
    }, DateTime(2026, 11, 19));

    await expectLater(store.importBackup(backup), throwsA(isA<StateError>()));
    expect(store.prefs.getString('edu.tasks'), damagedCiphertext);
    expect(store.prefs.getString('edu.profile'), beforeProfile);
    expect(store.dataError('edu.tasks'), isNotNull);
    expect(store.profile?['nickname'], 'قدیمی');
  });

}


class _FailingTasksCipher implements SecureLocalCipher {
  final MemorySecureLocalCipher _delegate = MemorySecureLocalCipher();

  @override
  Future<String> encrypt(String plaintext, {required String key}) async {
    if (key == 'edu.tasks' && plaintext.contains('new-task')) {
      throw StateError('simulated restore write failure');
    }
    return _delegate.encrypt(plaintext, key: key);
  }

  @override
  Future<String> decrypt(String ciphertext, {required String key}) async {
    if (key == 'edu.tasks') throw const FormatException('damaged task envelope');
    return _delegate.decrypt(ciphertext, key: key);
  }
}
