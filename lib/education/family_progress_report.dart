import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'education_store.dart';
import 'learning_engine.dart';
import 'ui.dart';

/// Builds a student-reviewed family summary. It excludes AI conversations,
/// wallet data, purchase tokens and personal identifiers.
String buildFamilyProgressReport({
  required Map<String, dynamic>? profile,
  required List<Entry> exams,
  required List<Entry> tasks,
  required List<Entry> cards,
  required List<Entry> deadlines,
  required DateTime now,
}) {
  final report = buildLearningReport(
    exams: exams,
    tasks: tasks,
    cards: cards,
    now: now,
  );
  final nickname = profile?['nickname']?.toString().trim() ?? '';
  final grade = profile?['grade']?.toString().trim() ?? '';
  final year = profile?['year']?.toString().trim() ?? '';
  final openTasks = tasks.where((task) => task['done'] != true).length;
  final completedTasks = tasks.length - openTasks;
  final dueCards = cards.where((card) => isCardDue(card, now)).length;
  final upcoming = deadlines.where((item) {
    final date = parseDay(item['date']);
    if (date == null) return false;
    final days = date.difference(startOfDay(now)).inDays;
    return days >= 0 && days <= 7;
  }).toList()
    ..sort((a, b) => parseDay(a['date'])!.compareTo(parseDay(b['date'])!));

  final lines = <String>[
    'گزارش پیشرفت تحصیلی سیمرغ',
    'تاریخ تهیه: ${isoDay(now)}',
    if (nickname.isNotEmpty) 'نام مستعار: $nickname',
    if (grade.isNotEmpty || year.isNotEmpty) 'مقطع و پایه: ${[grade, year].where((value) => value.isNotEmpty).join(' · ')}',
    '',
    '۱) وضعیت درس‌ها',
    if (report.subjects.isEmpty) 'هنوز نمره معتبری ثبت نشده است.',
    for (final subject in report.subjects)
      '- ${subject.subject}: میانگین ${subject.average.toStringAsFixed(1)}٪ از ${subject.examCount} آزمون${subject.trend == null ? '' : '؛ تغییر آخرین آزمون نسبت به میانگین قبلی: ${subject.trend! >= 0 ? '+' : ''}${subject.trend!.toStringAsFixed(1)} واحد درصد'}',
    '',
    '۲) برنامه و پیگیری',
    'کارهای ثبت‌شده: ${tasks.length} · تکمیل‌شده: $completedTasks · باز: $openTasks',
    'این تعداد، ثبت کارها را نشان می‌دهد و به‌تنهایی معادل میزان یادگیری نیست.',
    '',
    '۳) مرور و یادآوری',
    'فلش‌کارت‌های سررسیدشده: $dueCards',
    '',
    '۴) امتحان‌های هفت روز آینده',
    if (upcoming.isEmpty) 'امتحانی با تاریخ نزدیک ثبت نشده است.',
    for (final item in upcoming)
      '- ${item['subject'] ?? 'درس'} · ${item['date']}',
    '',
    '۵) یادآوری مهم',
    'این گزارش فقط خلاصه اطلاعاتی است که دانش‌آموز در برنامه ثبت کرده است. نمره‌ها و شاخص‌های مرور، آزمون استاندارد استعداد یا تشخیص قطعی تسلط نیستند. هدف، گفت‌وگوی حمایتی و برنامه‌ریزی واقع‌بینانه است؛ نه مقایسه، سرزنش یا فشار.',
    'گفت‌وگوهای خصوصی با مشاور هوش مصنوعی، اطلاعات کیف اعتبار و سوابق خرید در این گزارش قرار نمی‌گیرند.',
  ];
  return lines.join('\n');
}

class FamilyProgressReportPage extends StatelessWidget {
  const FamilyProgressReportPage({super.key, required this.store});
  final EducationStore store;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) {
      final report = buildFamilyProgressReport(
        profile: store.profile,
        exams: store.exams,
        tasks: store.tasks,
        cards: store.cards,
        deadlines: store.deadlines,
        now: DateTime.now(),
      );
      return Scaffold(
        appBar: AppBar(title: const Text('گزارش قابل اشتراک با خانواده')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const NoticeCard(
              text: 'این گزارش ابتدا فقط روی گوشی ساخته می‌شود. خودت آن را بخوان و فقط اگر راحت بودی، متن انتخابی را با خانواده به اشتراک بگذار. هیچ اطلاعاتی خودکار ارسال نمی‌شود.',
              icon: Icons.privacy_tip_outlined,
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(report, style: const TextStyle(height: 1.9)),
              ),
            ),
            FilledButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: report));
                if (context.mounted) showMessage(context, 'گزارش کپی شد؛ پیش از ارسال، یک بار آن را مرور کن.');
              },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('کپی گزارش برای ارسال دلخواه'),
            ),
            const NoticeCard(
              text: 'این گزارش برای حمایت و گفت‌وگو طراحی شده است، نه نظارت تنبیهی. زمان‌ها بر اساس مدت کارهای ثبت‌شده‌اند و زمان واقعی مطالعه را اندازه‌گیری نمی‌کنند.',
              icon: Icons.favorite_outline,
            ),
          ],
        ),
      );
    },
  );
}
