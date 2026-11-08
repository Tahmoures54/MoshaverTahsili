import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:moshaver_tahsili/education/ai_advisor_service.dart';

void main() {
  test('does not make a request when the API key is missing', () async {
    var called = false;
    final service = AiAdvisorService(
      apiKey: '',
      client: MockClient((request) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      service.ask(profile: null, history: const [], question: 'سلام'),
      throwsA(isA<Exception>().having(
        (error) => error.toString(),
        'message',
        contains('پیکربندی نشده'),
      )),
    );
    expect(called, isFalse);
    service.dispose();
  });

  test('sends the student context and parses a successful answer', () async {
    http.Request? captured;
    final service = AiAdvisorService(
      apiKey: 'test-key',
      endpoint: 'https://example.test/v1/chat/completions',
      model: 'test-model',
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'choices': [
              {'message': {'content': 'برای شروع، یک برنامه واقع‌بینانه بنویس.'}}
            ]
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final answer = await service.ask(
      profile: {'grade': 'متوسطه اول', 'field': 'عمومی', 'goal': 'بهبود ریاضی'},
      history: const [
        {'role': 'user', 'content': 'در ریاضی مشکل دارم.'},
        {'role': 'assistant', 'content': 'کدام مبحث؟'},
      ],
      question: 'برای من برنامه بده.',
    );

    expect(answer, 'برای شروع، یک برنامه واقع‌بینانه بنویس.');
    expect(captured!.url.toString(), 'https://example.test/v1/chat/completions');
    expect(captured!.headers['authorization'], 'Bearer test-key');
    final body = jsonDecode(captured!.body) as Map<String, dynamic>;
    expect(body['model'], 'test-model');
    final messages = body['messages'] as List<dynamic>;
    expect(messages[0]['role'], 'system');
    expect(messages[0]['content'], contains('متوسطه اول'));
    expect(messages[1]['content'], 'در ریاضی مشکل دارم.');
    expect(messages.last['content'], 'برای من برنامه بده.');
    service.dispose();
  });

  test('shows a helpful message when the provider rate-limits requests', () async {
    final service = AiAdvisorService(
      apiKey: 'test-key',
      client: MockClient((request) async => http.Response('rate limited', 429)),
    );

    await expectLater(
      service.ask(profile: null, history: const [], question: 'سلام'),
      throwsA(isA<Exception>().having(
        (error) => error.toString(),
        'message',
        contains('تعداد درخواست‌ها زیاد شده'),
      )),
    );
    service.dispose();
  });
}
