import 'package:flutter_test/flutter_test.dart';
import 'package:moshaver_tahsili/education/family_progress_report.dart';

void main() {
  test(
    'family report summarizes student-entered records without private AI or wallet data',
    () {
      final report = buildFamilyProgressReport(
        profile: {
          'nickname': 'دانش‌آموز',
          'grade': 'متوسطه دوم',
          'year': 'دهم',
        },
        exams: [
          {
            'subject': 'ریاضی',
            'score': 15,
            'max': 20,
            'createdAt': '2026-11-10T10:00:00',
          },
        ],
        tasks: [
          {
            'id': 'a',
            'title': 'تمرین',
            'minutes': 30,
            'done': true,
            'completedAt': '2026-11-17T10:00:00',
          },
          {
            'id': 'b',
            'title': 'مرور',
            'minutes': 20,
            'done': false,
            'dueDate': '2026-11-18',
          },
        ],
        cards: [
          {'id': 'c', 'dueAt': '2026-11-17T10:00:00'},
        ],
        deadlines: [
          {'subject': 'فیزیک', 'date': '2026-11-20'},
        ],
        now: DateTime(2026, 11, 18, 12),
      );
      expect(report, contains('ریاضی'));
      expect(report, contains('تکمیل‌شده: 1'));
      expect(report, contains('فلش‌کارت‌های سررسیدشده: 1'));
      expect(report, contains('فیزیک'));
      expect(report, contains('گفت‌وگوهای خصوصی'));
      expect(report, isNot(contains('کیف اعتبار:')));
      expect(report, isNot(contains('تمرین خصوصی')));
    },
  );

  test(
    'report explains when there is no evidence instead of inventing progress',
    () {
      final report = buildFamilyProgressReport(
        profile: null,
        exams: const [],
        tasks: const [],
        cards: const [],
        deadlines: const [],
        now: DateTime(2026, 11, 18),
      );
      expect(report, contains('هنوز نمره معتبری ثبت نشده است.'));
      expect(report, contains('معادل میزان یادگیری نیست'));
    },
  );
}
