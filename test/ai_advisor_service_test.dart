import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moshaver_tahsili/education/ai_advisor_service.dart';
import 'package:moshaver_tahsili/education/education_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Response answer(String text, {int status = 200}) => http.Response(
    jsonEncode({'choices': [{'message': {'content': text}}]}), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

Future<EducationStore> paidStore({int credits = 2}) async {
  SharedPreferences.setMockInitialValues({EducationStore.walletKey: jsonEncode({'successful_uses': 2, 'credits': credits, 'purchase_tokens': <String>[]})});
  return EducationStore.open();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('charges once for a successful paid answer', () async {
    final store = await paidStore();
    final service = AiAdvisorService(store: store, apiKey: 'test-key', client: MockClient((_) async => answer('پاسخ آزمایشی در تست')));
    expect(await service.ask(profile: null, history: const [], question: 'سلام', requestId: 'a'), 'پاسخ آزمایشی در تست');
    expect(store.credits, 1);
    service.dispose();
  });

  test('concurrent duplicate request IDs share one call and one charge', () async {
    final store = await paidStore();
    final gate = Completer<void>();
    var calls = 0;
    final service = AiAdvisorService(store: store, apiKey: 'test-key', client: MockClient((_) async { calls++; await gate.future; return answer('answer'); }));
    final first = service.ask(profile: null, history: const [], question: 'same', requestId: 'same-id');
    final second = service.ask(profile: null, history: const [], question: 'same', requestId: 'same-id');
    await Future<void>.delayed(Duration.zero);
    gate.complete();
    expect(await Future.wait([first, second]), ['answer', 'answer']);
    expect(calls, 1);
    expect(store.credits, 1);
    service.dispose();
  });

  test('retry after timeout reuses the reservation and never double charges', () async {
    final store = await paidStore();
    var calls = 0;
    final service = AiAdvisorService(store: store, apiKey: 'secret-test-key', client: MockClient((_) async {
      if (++calls == 1) throw TimeoutException('secret-test-key must not leak');
      return answer('Recovered');
    }));
    await expectLater(service.ask(profile: null, history: const [], question: 'q', requestId: 'retry'), throwsA(isA<AiException>()
        .having((error) => error.toString(), 'safe message', isNot(contains('secret-test-key')))));
    expect(store.credits, 2);
    expect(await service.ask(profile: null, history: const [], question: 'q', requestId: 'retry'), 'Recovered');
    expect(store.credits, 1);
    expect(calls, 2);
    service.dispose();
  });

  test('retry after provider 503 reuses the paid request and charges only on success', () async {
    final store = await paidStore(credits: 1);
    var calls = 0;
    final service = AiAdvisorService(
      store: store,
      apiKey: 'test-key',
      client: MockClient((_) async {
        calls++;
        return calls == 1 ? http.Response('unavailable', 503) : answer('Recovered after 503');
      }),
    );
    await expectLater(
      service.ask(profile: null, history: const [], question: 'q', requestId: 'server-retry'),
      throwsA(isA<AiException>()),
    );
    expect(store.credits, 1);
    expect(await service.ask(
      profile: null, history: const [], question: 'q', requestId: 'server-retry',
    ), 'Recovered after 503');
    expect(store.credits, 0);
    expect(calls, 2);
    final prefs = await SharedPreferences.getInstance();
    final wallet = jsonDecode(prefs.getString(EducationStore.walletKey)!) as Map<String, dynamic>;
    final ledger = (wallet['transactions'] as List).cast<Map<String, dynamic>>();
    final attempts = ledger.where((entry) => entry['kind'] == 'ai' &&
        entry['id'].toString().startsWith('server-retry-attempt-')).toList();
    expect(attempts.map((entry) => entry['status']).toList(), ['refunded', 'completed']);
    expect(ledger.where((entry) => entry['kind'] == 'refund')
        .map((entry) => entry['id']).toList(), ['server-retry-attempt-1-refund']);
    service.dispose();
  });

  test('a completed answer is returned after restart without network or another charge', () async {
    final store = await paidStore(credits: 1);
    final first = AiAdvisorService(store: store, apiKey: 'test-key', client: MockClient((_) async => answer('Saved')));
    await first.ask(profile: null, history: const [], question: 'q', requestId: 'persisted');
    first.dispose();
    final reopened = await EducationStore.open();
    var called = false;
    final second = AiAdvisorService(store: reopened, apiKey: 'test-key', client: MockClient((_) async { called = true; return answer('new'); }));
    expect(await second.ask(profile: null, history: const [], question: 'q', requestId: 'persisted'), 'Saved');
    expect(called, isFalse);
    expect(reopened.credits, 0);
    second.dispose();
  });

  for (final response in <http.Response>[
    http.Response('secret provider body', 500), http.Response('rate limited', 429),
    http.Response('not json', 200), answer(''),
    http.Response(jsonEncode({'choices': <dynamic>[]}), 200),
    http.Response(jsonEncode({'choices': [{'message': {'content': 42}}]}), 200),
  ]) {
    test('failed/invalid response ${response.statusCode}/${response.body.hashCode} does not charge', () async {
      final store = await paidStore();
      final service = AiAdvisorService(store: store, apiKey: 'test-key', client: MockClient((_) async => response));
      await expectLater(service.ask(profile: null, history: const [], question: 'q', requestId: 'failed'), throwsA(isA<AiException>()));
      expect(store.credits, 2);
      expect(store.creditHistory.where((item) => item['kind'] == 'ai').every((item) => item['status'] != 'completed'), isTrue);
      service.dispose();
    });
  }

  test('caps streamed response size and refunds its reservation', () async {
    final store = await paidStore();
    final service = AiAdvisorService(store: store, apiKey: 'test-key', client: MockClient((_) async => http.Response('x' * (AiAdvisorService.maxResponseBytes + 1), 200)));
    await expectLater(service.ask(profile: null, history: const [], question: 'q'), throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.response)));
    expect(store.credits, 2);
    service.dispose();
  });

  test('zero balance blocks network and missing key blocks network', () async {
    final store = await paidStore(credits: 0);
    var called = false;
    final client = MockClient((_) async { called = true; return answer('no'); });
    final noCredit = AiAdvisorService(store: store, apiKey: 'test-key', client: client);
    await expectLater(noCredit.ask(profile: null, history: const [], question: 'q'), throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.credits)));
    noCredit.dispose();
    final noKey = AiAdvisorService(apiKey: '', client: client);
    await expectLater(noKey.ask(profile: null, history: const [], question: 'q'), throwsA(isA<AiException>()));
    noKey.dispose();
    expect(called, isFalse);
  });

  test('normalizes base endpoint, sends bounded context and excludes failed messages', () async {
    http.Request? captured;
    final service = AiAdvisorService(apiKey: 'test-key', model: 'test-model',
        client: MockClient((request) async { captured = request; return answer('برای شروع برنامه واقع‌بینانه بنویس.'); }));
    final result = await service.ask(profile: {'grade': 'متوسطه اول', 'year': 'هفتم', 'field': 'عمومی', 'goal': 'بهبود ریاضی'},
        history: [
          ...List.generate(30, (i) => {'role': 'user', 'content': 'turn-$i', 'status': 'completed'}),
          {'role': 'assistant', 'content': 'network error', 'status': 'failed'},
        ], question: 'برای من برنامه بده.');
    expect(result, contains('برنامه'));
    expect(captured!.url.toString(), 'https://api.avalai.ir/v1/chat/completions');
    expect(captured!.headers['Authorization'], 'Bearer test-key');
    final body = jsonDecode(captured!.body) as Map<String, dynamic>;
    expect(body['model'], 'test-model');
    final messages = body['messages'] as List;
    expect(messages, hasLength(26));
    expect(Map<String, dynamic>.from(messages.first as Map)['content'], contains('هفتم'));
    expect(Map<String, dynamic>.from(messages[1] as Map)['content'], 'turn-6');
    expect(Map<String, dynamic>.from(messages.last as Map)['content'], 'برای من برنامه بده.');
    expect(captured!.body.contains('network error'), isFalse);
    service.dispose();
  });

  test('accepts legacy full endpoint but rejects insecure or credential-bearing URLs', () async {
    final valid = AiAdvisorService(apiKey: 'test-key', endpoint: 'https://example.test/v1/chat/completions/', client: MockClient((request) async {
      expect(request.url.path, '/v1/chat/completions'); return answer('ok');
    }));
    expect(await valid.ask(profile: null, history: const [], question: 'q'), 'ok');
    valid.dispose();
    for (final endpoint in ['http://example.test/v1', 'https://user:password@example.test/v1', 'https://example.test/v1?key=secret']) {
      final service = AiAdvisorService(apiKey: 'test-key', endpoint: endpoint, client: MockClient((_) async => answer('no')));
      await expectLater(service.ask(profile: null, history: const [], question: 'q'), throwsA(isA<AiException>()));
      service.dispose();
    }
  });

  test('rejects oversized input before making a request', () async {
    final service = AiAdvisorService(apiKey: 'test-key', client: MockClient((_) async => throw StateError('must not call')));
    await expectLater(service.ask(profile: null, history: const [], question: 'x' * 4001), throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.input)));
    service.dispose();
  });

  test('actual timeout is bounded and its error is safe', () async {
    final store = await paidStore();
    final never = Completer<http.Response>();
    final service = AiAdvisorService(store: store, apiKey: 'test-key', timeout: const Duration(milliseconds: 20), client: MockClient((_) => never.future));
    await expectLater(service.ask(profile: null, history: const [], question: 'q'), throwsA(isA<AiException>().having((e) => e.kind, 'kind', AiErrorKind.timeout)));
    expect(store.credits, 2);
    service.dispose();
  });
}
