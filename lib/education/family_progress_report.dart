import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'education_store.dart';
import 'learning_engine.dart';
import 'ui.dart';

const _familyReportMaxLabelLength = 80;

String _reportText(Object? value, {int limit = _familyReportMaxLabelLength}) {
  if (value == null) return '';
  final normalized = value
      .toString()
      .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (normalized.length <= limit) return normalized;
  return '${normalized.substring(0, limit - 1)}…';
}

/// Calendar-day distance, independent of daylight-saving transitions.
int _calendarDayDistance(DateTime from, DateTime to) {
  final fromUtc = DateTime.utc(from.year, from.month, from.day);
  final toUtc = DateTime.utc(to.year, to.month, to.day);
  return toUtc.difference(fromUtc).inDays;
}

/// Builds a student-reviewed family summary from locally stored learning data.
/// It deliberately excludes names, contact details, AI conversations, wallet
/// data, purchase tokens, and private advice history.
///
/// The report is a descriptive summary, not a standardized assessment or a
/// measure of intelligence, ability, or actual time spent studying.
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

  final grade = _reportText(profile?['grade'], limit: 40);
  final year = _reportText(profile?['year'], limit: 40);
  final openTasks = tasks.where((task) => task['done'] != true).length;
  final completedTasks = tasks.length - openTasks;
  final dueCards = report.dueCards;

  final today = startOfDay(now);
  final upcoming = deadlines
      .map((item) {
        final date = parseDay(item['date']);
        return (item: item, date: date);
      })
      .where((entry) {
        if (entry.date == null) return false;
        final days = _calendarDayDistance(today, entry.date!);
        return days >= 0 && days <= 7;
      })
      .toList()
    ..sort((a, b) => a.date!.compareTo(b.date!));

  final overdueDeadlines = deadlines.where((item) {
    final date = parseDay(item['date']);
    return date != null && _calendarDayDistance(today, date) < 0;
  }).length;

  final plannedMinutes = report.weeks.fold<int>(
    0,
    (total, week) => total + week.plannedMinutes,
  );
  final completedMinutes = report.weeks.fold<int>(
    0,
    (total, week) => total + week.completedMinutes,
  );

  final lines = <String>[
    'گزارش پیشرفت تحصیلی سیمرغ',
    'تاریخ تهیه: ${faNumber(isoDay(now))}',
    if (grade.isNotEmpty || year.isNotEmpty)
      'مقطع و پایه: ${[grade, year].where((value) => value.isNotEmpty).join(' · ')}',
    '',
    '۱) وضعیت درس‌ها',
    if (report.subjects.isEmpty) 'هنوز نمره معتبر و قابل محاسبه‌ای ثبت نشده است.',
    for (final subject in report.subjects)
      '- ${_reportText(subject.subject)}: میانگین ${faNumber(subject.average.toStringAsFixed(1))}٪ از ${faNumber(subject.examCount)} آزمون${subject.trend == null ? '' : '؛ آخرین نمره نسبت به میانگین آزمون‌های قبلی ${subject.trend! >= 0 ? '+' : ''}${faNumber(subject.trend!.toStringAsFixed(1))} واحد درصد'}',
    '',
    '۲) برنامه و پیگیری',
    'کارهای ثبت‌شده: ${faNumber(tasks.length)} · تکمیل‌شده: ${faNumber(completedTasks)} · باز: ${faNumber(openTasks)}',
    'در چهار هفته اخیر، زمان برنامه‌ریزی‌شده بر اساس مدت ثبت‌شده کارها ${faNumber(plannedMinutes)} دقیقه و زمان ثبت‌شده برای کارهای تکمیل‌شده ${faNumber(completedMinutes)} دقیقه بوده است.',
    if (report.adherence != null)
      'از ${faNumber(report.adherenceSample)} کار دارای موعد در بازه بررسی ۱۴ روزه، ${faNumber((report.adherence! * 100).round())}٪ تکمیل شده است.',
    'این اعداد از اطلاعات واردشده در برنامه به دست می‌آیند؛ معادل میزان یادگیری نیستند و زمان واقعی مطالعه یا کیفیت یادگیری را اندازه‌گیری نمی‌کنند.',
    '',
    '۳) مرور و یادآوری',
    'فلش‌کارت‌های آماده مرور: ${faNumber(dueCards)}',
    '',
    '۴) امتحان‌های هفت روز آینده',
    if (upcoming.isEmpty) 'امتحانی با تاریخ معتبر در هفت روز آینده ثبت نشده است.',
    for (final entry in upcoming)
      '- ${_reportText(entry.item['subject']).isEmpty ? 'درس نامشخص' : _reportText(entry.item['subject'])} · ${faNumber(isoDay(entry.date!))}',
    if (overdueDeadlines > 0)
      'امتحان‌های دارای تاریخ گذشته و ثبت‌شده: ${faNumber(overdueDeadlines)} مورد؛ تاریخ آن‌ها نیازمند بازبینی است.',
    '',
    '۵) محدودیت داده‌ها',
    if (report.dataGaps.isEmpty)
      'برای شاخص‌های پایه گزارش، داده کافی ثبت شده است؛ این موضوع به معنی ارزیابی کامل همه مهارت‌ها نیست.',
    for (final gap in report.dataGaps) '- $gap',
    '',
    '۶) یادآوری مهم',
    'این گزارش فقط خلاصه اطلاعاتی است که دانش‌آموز در برنامه ثبت کرده است. میانگین نمره و شاخص‌های مرور، آزمون استاندارد استعداد یا تشخیص قطعی تسلط نیستند. هدف، گفت‌وگوی حمایتی و برنامه‌ریزی واقع‌بینانه است؛ نه مقایسه، سرزنش یا فشار.',
    'نام، اطلاعات تماس، گفت‌وگوهای خصوصی با سیمرغ، اطلاعات کیف پرها و سوابق خرید در این گزارش قرار نمی‌گیرند.',
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

          const relevantKeys = [
            'edu.profile',
            'edu.exams',
            'edu.tasks',
            'edu.cards',
            'edu.deadlines',
          ];
          final readErrors = <String>[
            for (final key in relevantKeys)
              if (store.dataError(key) != null) store.dataError(key)!,
          ];
          final canCopy = readErrors.isEmpty;

          return Scaffold(
            appBar: AppBar(title: const Text('گزارش قابل اشتراک با خانواده')),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const NoticeCard(
                  text: 'این گزارش ابتدا فقط روی گوشی ساخته می‌شود. خودت آن را بخوان و فقط اگر راحت بودی، متن انتخابی را با خانواده به اشتراک بگذار. هیچ اطلاعاتی خودکار ارسال نمی‌شود.',
                  icon: Icons.privacy_tip_outlined,
                ),
                if (readErrors.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const NoticeCard(
                    text: 'بخشی از اطلاعات قبلی قابل خواندن نیست. برای جلوگیری از ارسال گزارشی ناقص یا گمراه‌کننده، کپی گزارش تا زمان بررسی اطلاعات غیرفعال است.',
                    icon: Icons.warning_amber_rounded,
                    warning: true,
                  ),
                  for (final error in readErrors)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        error,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                ],
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      report,
                      style: const TextStyle(height: 1.9),
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: canCopy
                      ? () async {
                          try {
                            await Clipboard.setData(ClipboardData(text: report));
                            if (context.mounted) {
                              showMessage(
                                context,
                                'گزارش کپی شد؛ پیش از ارسال، یک بار آن را مرور کن.',
                              );
                            }
                          } on PlatformException {
                            if (context.mounted) {
                              showMessage(context, 'کپی گزارش انجام نشد. دوباره تلاش کن.');
                            }
                          } on Object {
                            if (context.mounted) {
                              showMessage(context, 'کپی گزارش انجام نشد. دوباره تلاش کن.');
                            }
                          }
                        }
                      : null,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('کپی گزارش برای ارسال دلخواه'),
                ),
                const SizedBox(height: 8),
                const NoticeCard(
                  text: 'این گزارش برای حمایت و گفت‌وگو طراحی شده است، نه نظارت تنبیهی. زمان‌های نمایش‌داده‌شده بر اساس مدت کارهای ثبت‌شده‌اند و زمان واقعی مطالعه را اندازه‌گیری نمی‌کنند.',
                  icon: Icons.favorite_outline,
                ),
              ],
            ),
          );
        },
      );
}
