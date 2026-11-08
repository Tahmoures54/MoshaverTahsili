import 'package:flutter_test/flutter_test.dart';

import 'package:smart_mechanic/models/diagnosis_result.dart';

void main() {
  group('DiagnosisResult.tryParse — سیاست «پاسخ مستقیم»', () {
    test('پاسخ questions بک‌اند به کارت تشخیص کامل تبدیل می‌شود', () {
      final result = DiagnosisResult.tryParse({
        'responseMode': 'questions',
        'followUpRound': 2,
        'followUpQuestions': ['صدای توپُر شدن لاستیک با سرعت تغییر می‌کند؟'],
        'questionOptions': [
          {
            'question': 'صدا هنگام ترمز گرفتن بیشتر می‌شود؟',
            'options': ['بله', 'خیر', 'گاهی'],
          },
        ],
        'urgency': 'yellow',
        'statusSummary': 'نیاز به بررسی دقیق‌تر.',
      });

      expect(result, isNotNull);
      // حالت questions هرگز از پارس بیرون نمی‌آید.
      expect(result!.responseMode, ResponseMode.diagnosis);
      expect(result.followUpRound, 0);
      // سؤال‌های بجا مانده فقط به‌عنوان راهنمای اختیاری نگه داشته می‌شوند.
      expect(result.optionalHints.length, 2);
      expect(result.optionalHints.first, contains('لاستیک'));
      // گزینه‌ها داخل پرانتز می‌آیند، نه چیپ انتخاب اجباری.
      expect(result.optionalHints.last, contains('بله / خیر / گاهی'));
    });

    test('پاسخ diagnosis دست‌نخورده می‌ماند', () {
      final result = DiagnosisResult.tryParse({
        'responseMode': 'diagnosis',
        'urgency': 'red',
        'confidence': 'high',
        'statusSummary': 'خلاصه',
        'causes': [
          {
            'title': 'خرابی بلوک لاستیک',
            'probability': 'high',
            'why': 'سایش نامناسب',
            'costBand': 'low',
          },
        ],
        'nextStep': 'مراجعه به تعمیرگاه',
      });

      expect(result, isNotNull);
      expect(result!.responseMode, ResponseMode.diagnosis);
      expect(result.causes.length, 1);
      expect(result.causes.first.title, 'خرابی بلوک لاستیک');
      expect(result.optionalHints, isEmpty);
      expect(result.isUrgent, isTrue);
    });

    test('ورودی null خروجی null می‌دهد (fallback متنی)', () {
      expect(DiagnosisResult.tryParse(null), isNull);
    });
  });
}
