import 'package:flutter_test/flutter_test.dart';
import 'package:moshaver_tahsili/education/ai_safety_policy.dart';

void main() {
  test('detects explicit Persian self-harm intent', () {
    for (final message in [
      'می‌خوام خودمو بکشم',
      'قصد دارم به خودم آسیب بزنم',
      'دیگه نمی‌خوام زنده باشم',
      'کاش مرده بودم',
      'فکر می‌کنم به خودم آسیب بزنم',
      'به خودم صدمه زدم',
      'خودزنی کردم',
      'می‌خواهم به زندگیم پایان بدهم',
    ]) {
      final result = AiSafetyPolicy.assess(message);
      expect(result.shouldBlockRemoteAi, isTrue, reason: message);
      expect(result.localResponse, contains('تنها نمان'));
    }
  });

  test('normalizes Arabic letters and zero-width formatting characters', () {
    final result = AiSafetyPolicy.assess('مي‌خواهم خودم را بكشم');
    expect(result.shouldBlockRemoteAi, isTrue);
  });

  test('detects explicit English self-harm intent', () {
    expect(AiSafetyPolicy.assess('I want to kill myself').shouldBlockRemoteAi, isTrue);
    expect(AiSafetyPolicy.assess('I want to end my life').shouldBlockRemoteAi, isTrue);
  });

  test('does not block ordinary study stress or general questions', () {
    for (final message in [
      'از ریاضی ناامید شدم، برای امتحان کمکم کن',
      'خودکشی در ادبیات چه معنایی دارد؟',
      'برای مقاله درباره خودکشی مطالعه می‌کنم.',
      'چطور برای هفته آینده برنامه مطالعه بنویسم؟',
    ]) {
      expect(AiSafetyPolicy.assess(message).shouldBlockRemoteAi, isFalse, reason: message);
    }
  });
}
