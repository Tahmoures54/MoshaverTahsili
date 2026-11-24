import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'education_store.dart';
import 'learning_engine.dart';
import 'ui.dart';

const _familyReportMaxLabelLength = 80;

const _familyReportRelevantKeys = <String>[
  'edu.profile',
  'edu.exams',
  'edu.tasks',
  'edu.cards',
  'edu.deadlines',
];

/// Normalizes user-entered labels before including them in a plain-text report.
///
/// Removes control characters and hidden directional formatting. Truncation
/// uses Unicode code points to avoid splitting UTF-16 surrogate pairs.
String _reportText(
  Object? value, {
  int limit = _familyReportMaxLabelLength,
}) {
  if (value == null || limit <= 0) return '';

  final normalized = value
      .toString()
      .replaceAll(
        RegExp(
          r'[\u0000-\u001F\u007F-\u009F'
          r'\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069'
          r'\u2028\u2029\uFEFF]',
        ),
        ' ',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  final codePoints = normalized.runes.toList(growable: false);

  if (codePoints.length <= limit) return normalized;
  if (limit == 1) return '…';

  return '${String.fromCharCodes(codePoints.take(limit - 1))}…';
}

/// Calendar-day distance, independent of daylight-saving transitions.
int _calendarDayDistance(DateTime from, DateTime to) {
  final fromUtc = DateTime.utc(
    from.year,
    from.month,
    from.day,
  );

  final toUtc = DateTime.utc(
    to.year,
    to.month,
    to.day,
  );

  return toUtc.difference(fromUtc).inDays;
}

String _reportSubject(Object? value) {
  final subject = _reportText(value);
  return subject.isEmpty ? 'درس نامشخص' : subject;
}

String _reportPercentage(double value) {
  if (!value.isFinite) return 'نامشخص';
  return faNumber(value.toStringAsFixed(1));
}

String _reportTrend(double? value) {
  if (value == null || !value.isFinite) return '';

  // Avoid displaying negative zero after rounding.
  final rounded = double.parse(value.toStringAsFixed(1));

  final prefix = rounded > 0 ? '+' : '';

  return '؛ آخرین نمره نسبت به میانگین آزمون‌های قبلی '
      '$prefix${faNumber(rounded.toStringAsFixed(1))} '
      'واحد درصد';
}

/// Builds a student-reviewed family summary from local learning data.
///
/// Does not read dedicated name/contact fields, private conversations,
/// wallet data, purchase tokens or private advice history.
///
/// User-entered labels can still contain identifying information, so the
/// student must review the report before sharing.
///
/// This is descriptive, not a standardized assessment or a measurement of
/// intelligence, ability, learning mastery or actual time spent studying.
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

  final grade = _reportText(
    profile?['grade'],
    limit: 40,
  );

  final year = _reportText(
    profile?['year'],
    limit: 40,
  );

  final educationLabel = [
    grade,
    year,
  ].where((value) => value.isNotEmpty).join(' · ');

  final openTasks = tasks
      .where((task) => task['done'] != true)
      .length;

  final completedTasks = tasks.length - openTasks;

  final today = startOfDay(now);

  // Includes today and the next seven calendar days.
  final upcoming = deadlines
      .map((item) {
        final date = parseDay(item['date']);
        return (item: item, date: date);
      })
      .where((entry) {
        final date = entry.date;

        if (date == null) return false;

        final distance = _calendarDayDistance(today, date);

        return distance >= 0 && distance <= 7;
      })
      .toList()
    ..sort((a, b) {
      final dateOrder = a.date!.compareTo(b.date!);

      if (dateOrder != 0) return dateOrder;

      return _reportSubject(a.item['subject']).compareTo(
        _reportSubject(b.item['subject']),
      );
    });

  final overdueDeadlines = deadlines.where((item) {
    final date = parseDay(item['date']);

    return date != null &&
        _calendarDayDistance(today, date) < 0;
  }).length;

  final invalidDeadlineDates = deadlines.where((item) {
    return parseDay(item['date']) == null;
  }).length;

  final plannedMinutes = report.weeks.fold<int>(
    0,
    (total, week) => total + week.plannedMinutes,
  );

  final completedMinutes = report.weeks.fold<int>(
    0,
    (total, week) => total + week.completedMinutes,
  );

  final adherence = report.adherence;

  final hasValidAdherence = adherence != null &&
      adherence.isFinite &&
      adherence >= 0 &&
      adherence <= 1;

  final dataGaps = <String>[
    for (final gap in report.dataGaps)
      if (_reportText(gap, limit: 400).isNotEmpty)
        _reportText(gap, limit: 400),
    if (invalidDeadlineDates > 0)
      '${faNumber(invalidDeadlineDates)} امتحان ثبت‌شده '
          'تاریخ قابل خواندن ندارد و در فهرست موعدها '
          'محاسبه نشده است.',
    if (adherence != null && !hasValidAdherence)
      'شاخص پیگیری برنامه قابل محاسبه نیست '
          'و در گزارش نمایش داده نشده است.',
  ].toSet().toList(growable: false);

  final lines = <String>[
    'گزارش پیشرفت تحصیلی سیمرغ',
    'تاریخ تهیه: ${faNumber(isoDay(now))}',
    if (educationLabel.isNotEmpty)
      'مقطع و پایه: $educationLabel',
    '',
    '۱) وضعیت درس‌ها',
    if (report.subjects.isEmpty)
      'هنوز نمره معتبر و قابل محاسبه‌ای ثبت نشده است.',
    for (final subject in report.subjects)
      '- ${_reportSubject(subject.subject)}: '
          'میانگین ${_reportPercentage(subject.average)}٪ '
          'از ${faNumber(subject.examCount)} آزمون'
          '${_reportTrend(subject.trend)}',
    '',
    '۲) برنامه و پیگیری',
    'کارهای ثبت‌شده: ${faNumber(tasks.length)}'
        ' · تکمیل‌شده: ${faNumber(completedTasks)}'
        ' · باز: ${faNumber(openTasks)}',
    'در چهار هفته اخیر، زمان برنامه‌ریزی‌شده '
        'بر اساس مدت ثبت‌شده کارها '
        '${faNumber(plannedMinutes)} دقیقه '
        'و مجموع مدت ثبت‌شده کارهای تکمیل‌شده '
        '${faNumber(completedMinutes)} دقیقه بوده است.',
    if (hasValidAdherence)
      'از ${faNumber(report.adherenceSample)} کار دارای موعد '
          'در بازه بررسی ۱۴ روزه، '
          '${faNumber((adherence! * 100).round())}٪ '
          'تکمیل شده است.',
    'این اعداد از اطلاعات واردشده در برنامه به دست می‌آیند؛ '
        'زمان واقعی مطالعه یا کیفیت یادگیری را '
        'اندازه‌گیری نمی‌کنند.',
    '',
    '۳) مرور و یادآوری',
    'فلش‌کارت‌های آماده مرور: '
        '${faNumber(report.dueCards)}',
    '',
    '۴) امتحان‌های امروز و هفت روز آینده',
    if (upcoming.isEmpty)
      'امتحانی با تاریخ معتبر برای امروز '
          'و هفت روز آینده ثبت نشده است.',
    for (final entry in upcoming)
      '- ${_reportSubject(entry.item['subject'])}'
          ' · ${faNumber(isoDay(entry.date!))}',
    if (overdueDeadlines > 0)
      'امتحان‌های ثبت‌شده با تاریخ گذشته: '
          '${faNumber(overdueDeadlines)} مورد. '
          'این شمارش به معنی برگزارنشدن یا '
          'انجام‌نشدن امتحان نیست؛ '
          'در صورت نیاز، تاریخ‌های ثبت‌شده را بازبینی کن.',
    '',
    '۵) محدودیت داده‌ها',
    if (dataGaps.isEmpty)
      'برای شاخص‌های پایه گزارش، '
          'داده کافی ثبت شده است؛ '
          'این موضوع به معنی ارزیابی کامل '
          'همه مهارت‌ها نیست.',
    for (final gap in dataGaps) '- $gap',
    '',
    '۶) یادآوری مهم',
    'این گزارش فقط خلاصه اطلاعاتی است که '
        'دانش‌آموز در برنامه ثبت کرده است. '
        'میانگین نمره و شاخص‌های مرور، '
        'آزمون استاندارد استعداد یا تشخیص قطعی '
        'تسلط نیستند. هدف، گفت‌وگوی حمایتی و '
        'برنامه‌ریزی واقع‌بینانه است؛ '
        'نه مقایسه، سرزنش یا فشار.',
    'فیلدهای نام و اطلاعات تماس، '
        'گفت‌وگوهای خصوصی با سیمرغ، '
        'اطلاعات کیف پرها و سوابق خرید '
        'در این گزارش استفاده نمی‌شوند.',
    'اگر در نام درس، مقطع یا پایه، '
        'نام شخص یا اطلاعات خصوصی نوشته‌ای، '
        'ممکن است همان متن در گزارش دیده شود. '
        'پیش از ارسال، متن را بررسی '
        'و اطلاعات ناخواسته را حذف کن.',
  ];

  return lines.join('\n');
}

class _FamilyReportSnapshot {
  const _FamilyReportSnapshot({
    required this.errors,
    this.report,
  });

  final List<String> errors;
  final String? report;

  bool get canCopy => errors.isEmpty && report != null;
}

List<String> _familyReportReadErrors(EducationStore store) {
  return <String>{
    for (final key in _familyReportRelevantKeys)
      if (store.dataError(key) != null)
        store.dataError(key)!,
  }.toList(growable: false);
}

/// Reads all relevant sections before evaluating errors.
///
/// Some store getters discover corruption while reading, so checking errors
/// only before accessing the getters is insufficient.
_FamilyReportSnapshot _readFamilyReportSnapshot(
  EducationStore store,
  DateTime now,
) {
  final existingErrors = _familyReportReadErrors(store);

  if (existingErrors.isNotEmpty) {
    return _FamilyReportSnapshot(
      errors: existingErrors,
    );
  }

  try {
    final profile = store.profile;
    final exams = store.exams;
    final tasks = store.tasks;
    final cards = store.cards;
    final deadlines = store.deadlines;

    final readErrors = _familyReportReadErrors(store);

    if (readErrors.isNotEmpty) {
      return _FamilyReportSnapshot(
        errors: readErrors,
      );
    }

    final report = buildFamilyProgressReport(
      profile: profile,
      exams: exams,
      tasks: tasks,
      cards: cards,
      deadlines: deadlines,
      now: now,
    );

    return _FamilyReportSnapshot(
      errors: const [],
      report: report,
    );
  } on Object {
    // Do not expose exception details or underlying student data in the UI.
    final readErrors = _familyReportReadErrors(store);

    return _FamilyReportSnapshot(
      errors: readErrors.isNotEmpty
          ? readErrors
          : const [
              'ساخت گزارش از اطلاعات فعلی انجام نشد. '
                  'داده‌ها را بررسی کن و دوباره تلاش کن.',
            ],
    );
  }
}

class FamilyProgressReportPage extends StatefulWidget {
  const FamilyProgressReportPage({
    super.key,
    required this.store,
  });

  final EducationStore store;

  @override
  State<FamilyProgressReportPage> createState() =>
      _FamilyProgressReportPageState();
}

class _FamilyProgressReportPageState
    extends State<FamilyProgressReportPage> {
  bool _copying = false;

  Future<void> _copyReport(
    _FamilyReportSnapshot displayedSnapshot,
    DateTime reportTime,
  ) async {
    if (_copying ||
        !displayedSnapshot.canCopy ||
        !mounted) {
      return;
    }

    setState(() {
      _copying = true;
    });

    try {
      // Reuse the preview's timestamp so the comparison checks source data,
      // rather than merely detecting a changed report creation time.
      final currentSnapshot = _readFamilyReportSnapshot(
        widget.store,
        reportTime,
      );

      if (!currentSnapshot.canCopy) {
        if (mounted) {
          showMessage(
            context,
            'بخشی از اطلاعات قابل خواندن نیست؛ '
            'گزارش کپی نشد.',
          );
        }

        return;
      }

      if (currentSnapshot.report != displayedSnapshot.report) {
        if (mounted) {
          showMessage(
            context,
            'اطلاعات گزارش تغییر کرده است. '
            'نسخه تازه را مرور کن و دوباره کپی کن.',
          );
        }

        return;
      }

      await Clipboard.setData(
        ClipboardData(
          text: displayedSnapshot.report!,
        ),
      );

      if (mounted) {
        showMessage(
          context,
          'گزارش کپی شد؛ '
          'پیش از ارسال، یک بار آن را مرور کن.',
        );
      }
    } on PlatformException {
      if (mounted) {
        showMessage(
          context,
          'کپی گزارش انجام نشد. دوباره تلاش کن.',
        );
      }
    } on Object {
      if (mounted) {
        showMessage(
          context,
          'کپی گزارش انجام نشد. دوباره تلاش کن.',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _copying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final reportTime = DateTime.now();

        final snapshot = _readFamilyReportSnapshot(
          widget.store,
          reportTime,
        );

        return Scaffold(
          appBar: AppBar(
            title: const Text(
              'گزارش قابل اشتراک با خانواده',
            ),
          ),
          body: SafeArea(
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const NoticeCard(
                    text:
                        'این گزارش ابتدا فقط روی گوشی ساخته می‌شود. '
                        'خودت آن را بخوان و فقط اگر راحت بودی، '
                        'با خانواده به اشتراک بگذار. '
                        'هیچ اطلاعاتی خودکار ارسال نمی‌شود.',
                    icon: Icons.privacy_tip_outlined,
                  ),
                  const SizedBox(height: 12),
                  if (snapshot.errors.isNotEmpty) ...[
                    const NoticeCard(
                      text:
                          'بخشی از اطلاعات قابل خواندن نیست '
                          'یا ساخت گزارش انجام نشده است. '
                          'برای جلوگیری از اشتراک گزارشی '
                          'ناقص یا گمراه‌کننده، '
                          'نمایش و کپی گزارش فعلاً غیرفعال است.',
                      icon: Icons.warning_amber_rounded,
                      warning: true,
                    ),
                    for (final error in snapshot.errors)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: 8,
                        ),
                        child: Text(
                          error,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall,
                        ),
                      ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _copying
                          ? null
                          : () {
                              setState(() {});
                            },
                      icon: const Icon(
                        Icons.refresh_outlined,
                      ),
                      label: const Text(
                        'بررسی دوباره اطلاعات',
                      ),
                    ),
                  ] else if (snapshot.report != null) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(
                          snapshot.report!,
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(
                            height: 1.9,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  FilledButton.icon(
                    onPressed: snapshot.canCopy && !_copying
                        ? () => _copyReport(
                              snapshot,
                              reportTime,
                            )
                        : null,
                    icon: _copying
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.copy_outlined,
                          ),
                    label: Text(
                      _copying
                          ? 'در حال کپی گزارش…'
                          : 'کپی گزارش برای ارسال دلخواه',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const NoticeCard(
                    text:
                        'کپی، کل متن گزارش را در '
                        'کلیپ‌بورد دستگاه قرار می‌دهد. '
                        'اگر فقط بخشی را می‌خواهی ارسال کنی، '
                        'همان بخش را از متن انتخاب کن. '
                        'بسته به تنظیمات دستگاه، '
                        'کلیپ‌بورد ممکن است با دستگاه‌های '
                        'دیگر همگام شود.',
                    icon: Icons.content_paste_outlined,
                  ),
                  const SizedBox(height: 8),
                  const NoticeCard(
                    text:
                        'این گزارش برای حمایت و گفت‌وگو '
                        'طراحی شده است، نه نظارت تنبیهی. '
                        'زمان‌های نمایش‌داده‌شده بر اساس '
                        'مدت کارهای ثبت‌شده‌اند و '
                        'زمان واقعی مطالعه را '
                        'اندازه‌گیری نمی‌کنند.',
                    icon: Icons.favorite_outline,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
