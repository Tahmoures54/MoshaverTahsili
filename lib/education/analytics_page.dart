import 'package:flutter/material.dart';

import 'education_store.dart';
import 'learning_engine.dart';
import 'mastery_estimator.dart';
import 'ui.dart';

// ---------------------------------------------------------------------------
// Data validation
// ---------------------------------------------------------------------------

/// Missing or invalid data must not be presented as a recorded zero.
int? _validCount(Object? value) {
  if (value is int) {
    return value >= 0 ? value : null;
  }

  if (value is num) {
    if (!value.isFinite || value < 0) return null;

    final integer = value.toInt();
    return value == integer ? integer : null;
  }

  if (value is String) {
    final parsed = int.tryParse(digitsToEnglish(value.trim()));
    return parsed != null && parsed >= 0 ? parsed : null;
  }

  return null;
}

double? _validPercentage(Object? value) {
  if (value is! num || !value.isFinite) return null;

  final result = value.toDouble();

  if (result < 0 || result > 100) return null;

  return result;
}

double? _validProbability(Object? value) {
  if (value is! num || !value.isFinite) return null;

  final result = value.toDouble();

  if (result < 0 || result > 1) return null;

  return result;
}

String? _nonEmptyText(Object? value) {
  if (value is! String) return null;

  final text = value.trim();
  return text.isEmpty ? null : text;
}

String? _lessonStage(Entry lesson) {
  return _nonEmptyText(lesson['stage']);
}

String _percentageText(double percentage) {
  return '${faNumber(percentage.toStringAsFixed(1))}٪';
}

String _minutesText(int? minutes) {
  return minutes == null
      ? 'داده معتبر موجود نیست'
      : '${faNumber(minutes)} دقیقه';
}

/// The underlying engine uses Gregorian DateTime values.
/// Keep this label explicit rather than implying a Jalali conversion.
String _gregorianDateText(DateTime date) {
  final year = date.year.toString().padLeft(4, '0');
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');

  return faNumber('$year/$month/$day');
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

/// Local performance analytics.
///
/// This page computes its report locally and does not itself initiate
/// network requests.
///
/// It does not make guarantees about storage, synchronization or networking
/// elsewhere in the application.
class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key, required this.store});

  final EducationStore store;

  @override
  Widget build(BuildContext context) {
    // EducationStore's declaration is not assumed to implement Listenable.
    // If it does, subscribe to changes. Otherwise the parent must rebuild.
    final Object source = store;

    if (source is Listenable) {
      return ListenableBuilder(
        listenable: source,
        builder: (context, _) => _buildPage(context),
      );
    }

    return _buildPage(context);
  }

  Widget _buildPage(BuildContext context) {
    final report = buildLearningReport(
      exams: store.exams,
      tasks: store.tasks,
      cards: store.cards,
      now: DateTime.now(),
    );

    final topicMastery = estimateTopicMastery(store.cards);

    final allSessions = List<Entry>.of(store.teachingSessions);

    // Uses the store's existing order; this is not a timestamp sort.
    final recentSessions = allSessions.reversed.take(8).toList();

    final completedSessions = allSessions
        .where((lesson) => _lessonStage(lesson) == 'completed')
        .length;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تحلیل عملکرد تحصیلی'),
          centerTitle: false,
        ),
        body: SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              const NoticeCard(
                text:
                    'این صفحه گزارش را از داده‌های ثبت‌شده خودت محاسبه می‌کند '
                    'و برای ساخت آن درخواست شبکه‌ای ارسال نمی‌کند. '
                    'نتیجه‌ها نشانه‌هایی برای تصمیم‌گیری‌اند، '
                    'نه حکم قطعی درباره توانایی تو.',
                icon: Icons.insights_outlined,
              ),
              for (final gap in report.dataGaps)
                NoticeCard(text: gap, warning: true),
              _buildAcademicHighlights(report),
              _buildSubjectSection(report),
              _buildTopicSection(topicMastery),
              _buildTeachingSection(
                sessions: recentSessions,
                totalSessions: allSessions.length,
                completedSessions: completedSessions,
              ),
              _buildAdherenceSection(report),
              _buildWeeklySection(report.weeks),
              _buildReviewSection(report),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Academic highlights
  // -------------------------------------------------------------------------

  Widget _buildAcademicHighlights(LearningReport report) {
    final strengths = report.strengths
        .where((item) => _validPercentage(item.average) != null)
        .map((item) => item.subject)
        .toSet()
        .toList();

    final weaknesses = report.weaknesses
        .where((item) => _validPercentage(item.average) != null)
        .map((item) => item.subject)
        .toSet()
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (strengths.isNotEmpty)
          NoticeCard(
            text:
                'درس‌های با میانگین ثبت‌شده بالاتر: '
                '${strengths.join('، ')}',
            icon: Icons.emoji_events_outlined,
          ),
        if (weaknesses.isNotEmpty)
          NoticeCard(
            text:
                'درس‌های پیشنهادی برای تمرین بیشتر: '
                '${weaknesses.join('، ')}',
            warning: true,
          ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Subject performance
  // -------------------------------------------------------------------------

  Widget _buildSubjectSection(LearningReport report) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('میانگین درس‌ها'),
        if (report.subjects.isEmpty)
          const EmptyState(
            title: 'هنوز داده‌ای نداریم',
            subtitle:
                'با ثبت نمره معتبر و نام درس، '
                'میانگین و روند هر درس نمایش داده می‌شود.',
            icon: Icons.assessment_outlined,
          ),
        for (final subject in report.subjects) _buildSubjectCard(subject),
      ],
    );
  }

  Widget _buildSubjectCard(SubjectProgress subject) {
    final average = _validPercentage(subject.average);
    final title = _nonEmptyText(subject.subject) ?? 'درس بدون نام';

    return _contentCard(
      children: [
        _titleAndValue(
          title: title,
          value: average == null ? 'نامعتبر' : _percentageText(average),
        ),
        const SizedBox(height: 10),
        if (average != null)
          _progress(label: 'میانگین درس $title', percentage: average)
        else
          const Text(
            'میانگین معتبر برای نمایش موجود نیست.',
            style: TextStyle(height: 1.8),
          ),
        const SizedBox(height: 8),
        Text(
          _trendText(subject),
          style: const TextStyle(fontSize: 13, height: 1.8),
        ),
      ],
    );
  }

  String _trendText(SubjectProgress subject) {
    final count = _validCount(subject.examCount);

    if (count == null) {
      return 'تعداد نمره‌های ثبت‌شده معتبر نیست.';
    }

    final prefix = '${faNumber(count)} نمره معتبر ثبت شده است.';

    if (count < 2) {
      return '$prefix برای مقایسه روند، حداقل دو نمره لازم است.';
    }

    final trend = subject.trend;

    if (trend == null || !trend.isFinite || trend < -100 || trend > 100) {
      return '$prefix داده معتبر برای مقایسه روند موجود نیست.';
    }

    if (trend >= 3) {
      return '$prefix آخرین نمره حدود '
          '${faNumber(trend.round())} واحد درصد '
          'بالاتر از میانگین نمره‌های قبلی است.';
    }

    if (trend <= -3) {
      return '$prefix آخرین نمره حدود '
          '${faNumber(trend.abs().round())} واحد درصد '
          'پایین‌تر از میانگین نمره‌های قبلی است.';
    }

    return '$prefix آخرین نمره نزدیک به میانگین نمره‌های قبلی است.';
  }

  // -------------------------------------------------------------------------
  // Topic mastery
  // -------------------------------------------------------------------------

  Widget _buildTopicSection(List<TopicMastery> topics) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('شواهد یادگیری به تفکیک مبحث'),
        if (topics.isEmpty)
          const EmptyState(
            title: 'هنوز شواهد موضوعی ثبت نشده',
            subtitle:
                'برای فلش‌کارت‌ها نام مبحث ثبت کن و پس از مرور، '
                'نتیجه یادآوری را ارزیابی کن.',
            icon: Icons.school_outlined,
          ),
        for (final topic in topics) _buildTopicCard(topic),
        if (topics.isNotEmpty)
          const NoticeCard(
            text:
                'این برآورد از مرورهای ثبت‌شده فلش‌کارت‌ها ساخته می‌شود '
                'و به بعضی کیفیت‌های یادآوری وزن متفاوت می‌دهد. '
                'بازه نمایش‌داده‌شده تقریبی است؛ '
                'نمره امتحان یا احتمال قطعی موفقیت نیست. '
                'مرورهای تکراری یک کارت نیز شواهد مستقل محسوب نمی‌شوند.',
            icon: Icons.info_outline,
          ),
      ],
    );
  }

  Widget _buildTopicCard(TopicMastery item) {
    final title = _nonEmptyText(item.topic) ?? 'مبحث بدون نام';

    final estimate = _validProbability(item.estimate);
    final lower = _validProbability(item.lowerBound);
    final upper = _validProbability(item.upperBound);

    final hasValidInterval =
        estimate != null &&
        lower != null &&
        upper != null &&
        lower <= estimate &&
        estimate <= upper;

    final count = _validCount(item.evidenceCount);
    final successes = _validCount(item.successes);

    final hasValidCounts =
        count != null && successes != null && successes <= count;

    final evidenceText = hasValidCounts
        ? '${faNumber(count)} مرور معتبر · '
              '${faNumber(successes)} یادآوری موفق'
        : 'تعداد شواهد معتبر موجود نیست';

    final intervalText = hasValidInterval
        ? 'بازه تقریبی برآورد: '
              '${faNumber((lower * 100).toStringAsFixed(1))} تا '
              '${faNumber((upper * 100).toStringAsFixed(1))} درصد'
        : 'بازه برآورد معتبر موجود نیست';

    final confidence = _nonEmptyText(item.confidence);

    return _contentCard(
      children: [
        _titleAndValue(
          title: title,
          value: estimate == null ? 'نامعتبر' : _percentageText(estimate * 100),
        ),
        const SizedBox(height: 10),
        if (estimate != null)
          _progress(
            label: 'برآورد یادآوری مبحث $title',
            percentage: estimate * 100,
          )
        else
          const Text(
            'برآورد معتبر برای نمایش موجود نیست.',
            style: TextStyle(height: 1.8),
          ),
        const SizedBox(height: 8),
        Text(evidenceText, style: const TextStyle(fontSize: 12, height: 1.8)),
        Text(intervalText, style: const TextStyle(fontSize: 12, height: 1.8)),
        if (confidence != null && hasValidCounts)
          Text(
            'برچسب حجم شواهد: $confidence',
            style: const TextStyle(fontSize: 12, height: 1.8),
          ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Teaching sessions
  // -------------------------------------------------------------------------

  Widget _buildTeachingSection({
    required List<Entry> sessions,
    required int totalSessions,
    required int completedSessions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('یادگیری با سیمرغ'),
        if (totalSessions == 0)
          const EmptyState(
            title: 'هنوز جلسه تدریسی ثبت نشده',
            subtitle:
                'از صفحه گفت‌وگوی سیمرغ '
                'یک مبحث را برای یادگیری انتخاب کن.',
            icon: Icons.school_outlined,
          )
        else ...[
          _contentCard(
            children: [
              Wrap(
                spacing: 28,
                runSpacing: 16,
                children: [
                  _metric('جلسه‌های ثبت‌شده', totalSessions),
                  _metric('جلسه‌های تکمیل‌شده', completedSessions),
                ],
              ),
            ],
          ),
          if (totalSessions > sessions.length)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text(
                '${faNumber(sessions.length)} جلسه پایانی '
                'در ترتیب ذخیره‌شده نمایش داده می‌شود.',
                style: const TextStyle(fontSize: 12, height: 1.8),
              ),
            ),
          for (final lesson in sessions) _buildTeachingCard(lesson),
          const NoticeCard(
            text:
                'وضعیت «تکمیل‌شده» مطابق رکورد ذخیره‌شده جلسه است. '
                'این شاخص جایگزین نمره امتحان یا ارزیابی معلم نیست.',
            icon: Icons.info_outline,
          ),
        ],
      ],
    );
  }

  Widget _metric(String label, int value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          faNumber(value),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 12, height: 1.7)),
      ],
    );
  }

  Widget _buildTeachingCard(Entry lesson) {
    final stage = _lessonStage(lesson);
    final completed = stage == 'completed';
    final topic = _nonEmptyText(lesson['topic']) ?? 'مبحث بدون نام';

    final diagnostic = _validCount(lesson['diagnosticCount']);
    final correct = _validCount(lesson['masteryCorrect']);

    return _contentCard(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              completed ? Icons.task_alt : Icons.menu_book_outlined,
              color: completed ? teal : null,
              size: 27,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    topic,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _teachingStageText(stage),
                    style: const TextStyle(fontSize: 12, height: 1.8),
                  ),
                  Text(
                    diagnostic == null
                        ? 'تعداد ارزیابی آغازین ثبت نشده یا نامعتبر است.'
                        : '${faNumber(diagnostic)} ارزیابی آغازین ثبت‌شده',
                    style: const TextStyle(fontSize: 12, height: 1.8),
                  ),
                  Text(
                    correct == null
                        ? 'تعداد پاسخ‌های درست پایانی '
                              'ثبت نشده یا نامعتبر است.'
                        : '${faNumber(correct)} پاسخ درست '
                              'در سنجش پایانی',
                    style: const TextStyle(fontSize: 12, height: 1.8),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _teachingStageText(String? stage) {
    switch (stage) {
      case 'diagnostic':
        return 'ارزیابی آغازین';
      case 'explanation':
        return 'توضیح درس';
      case 'guidedPractice':
        return 'تمرین هدایت‌شده';
      case 'reteach':
        return 'بازآموزی';
      case 'masteryCheck':
        return 'سنجش یادگیری';
      case 'completed':
        return 'تکمیل‌شده';
      default:
        return 'وضعیت نامشخص';
    }
  }

  // -------------------------------------------------------------------------
  // Study plan adherence
  // -------------------------------------------------------------------------

  Widget _buildAdherenceSection(LearningReport report) {
    final adherence = _validProbability(report.adherence);
    final sample = _validCount(report.adherenceSample);

    final hasData = adherence != null && sample != null && sample > 0;

    final noRecords = report.adherence == null && report.adherenceSample == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('پایبندی به برنامه'),
        _contentCard(
          children: [
            if (!hasData)
              Text(
                noRecords
                    ? 'در بازه بررسی، کاری با موعد گذشته ثبت نشده است.'
                    : 'داده معتبر برای محاسبه پایبندی موجود نیست.',
                style: const TextStyle(height: 1.8),
              )
            else ...[
              _titleAndValue(
                title: 'انجام کارهای با موعد گذشته',
                value: _percentageText(adherence * 100),
              ),
              const SizedBox(height: 12),
              _progress(
                label: 'پایبندی به برنامه مطالعه',
                percentage: adherence * 100,
              ),
              const SizedBox(height: 10),
              Text(
                'از ${faNumber(sample)} کار با موعد گذشته '
                'در ۱۴ روز پیش از امروز، '
                '${_percentageText(adherence * 100)} '
                'در حال حاضر انجام‌شده علامت خورده است.',
                style: const TextStyle(fontSize: 13, height: 1.8),
              ),
              const SizedBox(height: 6),
              const Text(
                'این شاخص انجام‌شدن کار را می‌سنجد، '
                'نه لزوماً انجام آن پیش از موعد.',
                style: TextStyle(fontSize: 12, height: 1.8),
              ),
            ],
          ],
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Weekly study chart
  // -------------------------------------------------------------------------

  Widget _buildWeeklySection(List<WeekLoad> weeks) {
    var maximum = 1;
    var hasPositiveMinutes = false;
    var hasInvalidMinutes = false;

    for (final week in weeks) {
      for (final raw in [week.plannedMinutes, week.completedMinutes]) {
        final minutes = _validCount(raw);

        if (minutes == null) {
          hasInvalidMinutes = true;
          continue;
        }

        if (minutes > 0) hasPositiveMinutes = true;
        if (minutes > maximum) maximum = minutes;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('مطالعه در چهار بازه هفت‌روزه اخیر'),
        if (weeks.isEmpty)
          const EmptyState(
            title: 'داده‌ای برای نمودار وجود ندارد',
            subtitle:
                'با ثبت برنامه و انجام فعالیت‌های مطالعه، '
                'گزارش نمایش داده می‌شود.',
            icon: Icons.bar_chart_outlined,
          )
        else ...[
          if (hasInvalidMinutes)
            const NoticeCard(
              text:
                  'بعضی مجموع‌های زمانی نامعتبرند '
                  'و میله آن‌ها رسم نشده است.',
              warning: true,
            ),
          if (!hasPositiveMinutes && !hasInvalidMinutes)
            const NoticeCard(
              text:
                  'در این بازه‌ها زمان مثبتی در گزارش ثبت نشده است. '
                  'این موضوع به معنی مطالعه‌نکردن نیست.',
              icon: Icons.info_outline,
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final textScale =
                          MediaQuery.textScalerOf(context).scale(12) / 12;

                      final columnWidth =
                          112.0 * textScale.clamp(1.0, 2.5).toDouble();

                      final minimumWidth = columnWidth * weeks.length;

                      final chartWidth = constraints.maxWidth > minimumWidth
                          ? constraints.maxWidth
                          : minimumWidth;

                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: chartWidth,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < weeks.length; i++)
                                Expanded(
                                  child: _weekColumn(weeks[i], i + 1, maximum),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  const Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 16,
                    runSpacing: 10,
                    children: [
                      _ChartLegend(
                        color: Color(0xFFBDBDBD),
                        label: 'برنامه‌ریزی‌شده',
                      ),
                      _ChartLegend(color: teal, label: 'انجام‌شده'),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const NoticeCard(
            text:
                'هر ستون یک بازه هفت‌روزه است، نه هفته تقویمی. '
                'برنامه‌ریزی‌شده بر اساس موعد کار و انجام‌شده '
                'بر اساس تاریخ تکمیل ثبت‌شده محاسبه می‌شود. '
                'زمان‌ها مدت ثبت‌شده کارها هستند، '
                'نه اندازه‌گیری خودکار زمان مطالعه.',
            icon: Icons.info_outline,
          ),
        ],
      ],
    );
  }

  Widget _weekColumn(WeekLoad week, int number, int maximum) {
    final planned = _validCount(week.plannedMinutes);
    final completed = _validCount(week.completedMinutes);

    double heightFor(int? minutes) {
      if (minutes == null || minutes == 0) return 0;

      final denominator = maximum > 0 ? maximum : 1;

      return (minutes / denominator * 110).clamp(0.0, 110.0).toDouble();
    }

    return Semantics(
      label:
          'بازه ${faNumber(number)}، '
          'از ${_gregorianDateText(week.start)} میلادی',
      value:
          'برنامه‌ریزی‌شده: ${_minutesText(planned)}، '
          'انجام‌شده: ${_minutesText(completed)}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            children: [
              SizedBox(
                height: 112,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _bar(heightFor(planned), const Color(0xFFBDBDBD)),
                      const SizedBox(width: 6),
                      _bar(heightFor(completed), teal),
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              const SizedBox(height: 8),
              Text(
                'بازه ${faNumber(number)}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'از ${_gregorianDateText(week.start)}\nمیلادی',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, height: 1.6),
              ),
              const SizedBox(height: 6),
              Text(
                'برنامه: ${_minutesText(planned)}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, height: 1.7),
              ),
              Text(
                'انجام: ${_minutesText(completed)}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, height: 1.7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bar(double height, Color color) {
    if (height <= 0) {
      return const SizedBox(width: 14);
    }

    return Container(
      width: 14,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Due flashcards
  // -------------------------------------------------------------------------

  Widget _buildReviewSection(LearningReport report) {
    final dueCards = _validCount(report.dueCards);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('مرور فلش‌کارت‌ها'),
        _contentCard(
          children: [
            Text(
              dueCards == null
                  ? 'تعداد معتبر کارت‌های آماده مرور موجود نیست.'
                  : dueCards == 0
                  ? 'در زمان تهیه گزارش، کارتی آماده مرور نیست.'
                  : '${faNumber(dueCards)} فلش‌کارت '
                        'در زمان تهیه گزارش آماده مرور است.',
              style: const TextStyle(height: 1.8),
            ),
            const SizedBox(height: 6),
            const Text(
              'در منطق فعلی برنامه، کارت بدون تاریخ مرور معتبر '
              'نیز آماده مرور محسوب می‌شود.',
              style: TextStyle(fontSize: 12, height: 1.8),
            ),
          ],
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Common UI
  // -------------------------------------------------------------------------

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _contentCard({required List<Widget> children}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _titleAndValue({required String title, required String value}) {
    // Wrap avoids forcing large text into a narrow fixed-height row.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 8,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    );
  }

  Widget _progress({required String label, required double percentage}) {
    final valid = _validPercentage(percentage);

    if (valid == null) {
      return const Text('داده معتبر برای نمایش موجود نیست.');
    }

    return Semantics(
      label: label,
      value: '${faNumber(valid.toStringAsFixed(1))} درصد',
      child: ExcludeSemantics(
        child: LinearProgressIndicator(
          value: valid / 100,
          minHeight: 8,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chart legend
// ---------------------------------------------------------------------------

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label, style: const TextStyle(fontSize: 12, height: 1.7)),
        ),
      ],
    );
  }
}
