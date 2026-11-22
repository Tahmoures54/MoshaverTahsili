
import 'package:flutter/material.dart';

import 'education_store.dart';
import 'learning_engine.dart';
import 'mastery_estimator.dart';
import 'ui.dart';

/// Converts potentially incomplete numeric values into safe non-negative
/// integers. Persian and Arabic digits are supported.
int _safeLessonCount(Object? value) {
  if (value is int && value >= 0) return value;

  if (value is num && value.isFinite && value >= 0) {
    return value.toInt();
  }

  final parsed = int.tryParse(
    digitsToEnglish(value?.toString() ?? ''),
  );

  return parsed != null && parsed >= 0 ? parsed : 0;
}

/// Converts a percentage into a safe progress-indicator value.
double _safeProgress(double value) {
  if (!value.isFinite) return 0;
  return value.clamp(0.0, 1.0).toDouble();
}

/// Converts a percentage into a safe display value.
double _safePercentage(double value) {
  if (!value.isFinite) return 0;
  return value.clamp(0.0, 100.0).toDouble();
}

/// Local performance analytics.
///
/// All displayed metrics are derived from the student's own records.
/// Missing evidence is never replaced with invented data.
///
/// This page does not upload student records to remote services.
class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({
    super.key,
    required this.store,
  });

  final EducationStore store;

  @override
  Widget build(BuildContext context) {
    final report = buildLearningReport(
      exams: store.exams,
      tasks: store.tasks,
      cards: store.cards,
      now: DateTime.now(),
    );

    final topicMastery = estimateTopicMastery(store.cards);

    // Display only the eight most recent teaching sessions.
    final teachingSessions = store.teachingSessions.reversed
        .take(8)
        .toList();

    final totalSessions = store.teachingSessions.length;

    final completedLessons = store.teachingSessions
        .where((item) => item['stage'] == 'completed')
        .length;

    // Calculate a safe chart maximum.
    var maxMinutes = 1;

    for (final week in report.weeks) {
      if (week.plannedMinutes > maxMinutes) {
        maxMinutes = week.plannedMinutes;
      }

      if (week.completedMinutes > maxMinutes) {
        maxMinutes = week.completedMinutes;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('تحلیل عملکرد تحصیلی'),
        centerTitle: false,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _buildIntroduction(),

          // Data quality warnings.
          for (final gap in report.dataGaps)
            NoticeCard(
              text: gap,
              warning: true,
            ),

          // General academic overview.
          _buildAcademicHighlights(report),

          // Subject performance.
          _buildSubjectSection(report),

          // Topic-level mastery.
          _buildTopicSection(topicMastery),

          // Teaching sessions.
          _buildTeachingSection(
            sessions: teachingSessions,
            totalSessions: totalSessions,
            completedLessons: completedLessons,
          ),

          // Study plan adherence.
          _buildAdherenceSection(report),

          // Weekly study activity.
          _buildWeeklySection(report.weeks, maxMinutes),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Introduction
  // ---------------------------------------------------------------------------

  Widget _buildIntroduction() {
    return const NoticeCard(
      text: 'این تحلیل فقط از داده‌های ثبت‌شده خودت ساخته می‌شود و روی گوشی می‌ماند. '
          'نتیجه‌ها نشانه‌هایی برای تصمیم‌گیری‌اند، نه حکم قطعی درباره توانایی تو.',
      icon: Icons.insights_outlined,
    );
  }

  // ---------------------------------------------------------------------------
  // Academic highlights
  // ---------------------------------------------------------------------------

  Widget _buildAcademicHighlights(LearningReport report) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (report.strengths.isNotEmpty)
          NoticeCard(
            text: 'نقاط قوت: '
                '${report.strengths.map((s) => s.subject).join('، ')}',
            icon: Icons.emoji_events_outlined,
          ),

        if (report.weaknesses.isNotEmpty)
          NoticeCard(
            text: 'درس‌های نیازمند تمرین بیشتر: '
                '${report.weaknesses.map((s) => s.subject).join('، ')}',
            warning: true,
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Subject performance
  // ---------------------------------------------------------------------------

  Widget _buildSubjectSection(LearningReport report) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('میانگین درس‌ها'),

        if (report.subjects.isEmpty)
          const EmptyState(
            title: 'هنوز داده‌ای نداریم',
            subtitle: 'با ثبت نمره آزمون، میانگین و روند هر درس نمایش داده می‌شود.',
            icon: Icons.assessment_outlined,
          ),

        for (final subject in report.subjects)
          _buildSubjectCard(subject),
      ],
    );
  }

  Widget _buildSubjectCard(SubjectProgress subject) {
    final average = _safePercentage(subject.average);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    subject.subject,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${faNumber(average.toStringAsFixed(1))}٪',
                  style: const TextStyle(
                    color: blue,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            Semantics(
              label: 'میانگین درس ${subject.subject}',
              value: '${average.toStringAsFixed(1)} درصد',
              child: LinearProgressIndicator(
                value: _safeProgress(average / 100),
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
              ),
            ),

            const SizedBox(height: 8),

            Text(
              _trendText(subject),
              style: const TextStyle(
                fontSize: 13,
                height: 1.7,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Topic mastery
  // ---------------------------------------------------------------------------

  Widget _buildTopicSection(List<dynamic> topicMastery) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('شواهد یادگیری به تفکیک مبحث'),

        if (topicMastery.isEmpty)
          const EmptyState(
            title: 'هنوز شواهد موضوعی ثبت نشده',
            subtitle: 'برای هر فلش‌کارت، نام مبحث را ثبت کن و پس از مرور، '
                'نتیجه یادآوری را ارزیابی کن.',
            icon: Icons.school_outlined,
          ),

        for (final item in topicMastery)
          _buildTopicCard(item),

        const NoticeCard(
          text: 'این درصد، برآوردی از سابقه یادآوری فلش‌کارت‌هاست؛ '
              'نمره امتحان یا احتمال قطعی موفقیت نیست. '
              'شواهد بیشتر، برآورد را قابل اتکاتر می‌کند.',
          icon: Icons.info_outline,
        ),
      ],
    );
  }

  Widget _buildTopicCard(dynamic item) {
    final estimate = _safeProgress(item.estimate as double);

    final lowerBound = _safePercentage(
      (item.lowerBound as num).toDouble() * 100,
    );

    final upperBound = _safePercentage(
      (item.upperBound as num).toDouble() * 100,
    );

    final evidenceCount = _safeLessonCount(item.evidenceCount);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.topic.toString(),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  '${faNumber((estimate * 100).round())}٪',
                  style: const TextStyle(
                    color: blue,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            Semantics(
              label: 'برآورد یادگیری ${item.topic}',
              value: '${(estimate * 100).round()} درصد',
              child: LinearProgressIndicator(
                value: estimate,
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
              ),
            ),

            const SizedBox(height: 8),

            Text(
              '${item.confidence} · '
              '${faNumber(evidenceCount)} مرور ثبت‌شده · '
              'بازه برآورد '
              '${faNumber(lowerBound.round())} تا '
              '${faNumber(upperBound.round())} درصد',
              style: const TextStyle(
                fontSize: 12,
                height: 1.8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Teaching sessions
  // ---------------------------------------------------------------------------

  Widget _buildTeachingSection({
    required List<Map<String, dynamic>> sessions,
    required int totalSessions,
    required int completedLessons,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('یادگیری با سیمرغ'),

        if (totalSessions == 0)
          const EmptyState(
            title: 'هنوز جلسه تدریسی ثبت نشده',
            subtitle: 'از صفحه گفت‌وگوی سیمرغ یک مبحث را برای یادگیری انتخاب کن.',
            icon: Icons.school_outlined,
          )
        else ...[
          _buildTeachingSummary(
            totalSessions,
            completedLessons,
          ),

          for (final lesson in sessions)
            _buildTeachingCard(lesson),

          const NoticeCard(
            text: 'تکمیل جلسه یعنی عبور از معیار داخلی تمرین و سنجش این جلسه؛ '
                'این شاخص جایگزین نمره امتحان یا ارزیابی معلم نیست.',
            icon: Icons.info_outline,
          ),
        ],
      ],
    );
  }

  Widget _buildTeachingSummary(
    int totalSessions,
    int completedLessons,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              child: _teachingMetric(
                'جلسه‌های ثبت‌شده',
                totalSessions,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _teachingMetric(
                'جلسه‌های تکمیل‌شده',
                completedLessons,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _teachingMetric(String label, int value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          faNumber(value),
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: blue,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildTeachingCard(Map<String, dynamic> lesson) {
    final stage = lesson['stage']?.toString();

    final isCompleted = stage == 'completed';

    final topic = lesson['topic']?.toString().trim();

    final diagnosticCount = _safeLessonCount(
      lesson['diagnosticCount'],
    );

    final masteryCorrect = _safeLessonCount(
      lesson['masteryCorrect'],
    );

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 6,
        ),
        leading: Icon(
          isCompleted
              ? Icons.task_alt
              : Icons.menu_book_outlined,
          color: isCompleted ? teal : blue,
          size: 27,
        ),
        title: Text(
          topic == null || topic.isEmpty
              ? 'مبحث بدون نام'
              : topic,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          '${_teachingStageText(stage)} · '
          '${faNumber(diagnosticCount)} ارزیابی آغازین · '
          '${faNumber(masteryCorrect)} پاسخ درست در سنجش پایانی',
          style: const TextStyle(
            height: 1.8,
            fontSize: 12,
          ),
        ),
        isThreeLine: true,
      ),
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

  // ---------------------------------------------------------------------------
  // Study plan adherence
  // ---------------------------------------------------------------------------

  Widget _buildAdherenceSection(LearningReport report) {
    final adherence = report.adherence;
    final hasData = adherence != null && adherence.isFinite;
    final percentage = _safePercentage((adherence ?? 0) * 100);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('پایبندی به برنامه'),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!hasData)
                  const Text(
                    'هنوز کار با موعد گذشته‌ای برای سنجش نداریم.',
                    style: TextStyle(height: 1.8),
                  )
                else ...[
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'میزان انجام کارهای موعددار',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${faNumber(percentage.round())}٪',
                        style: const TextStyle(
                          color: blue,
                          fontSize: 19,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Semantics(
                    label: 'پایبندی به برنامه مطالعه',
                    value: '${percentage.round()} درصد',
                    child: LinearProgressIndicator(
                      value: _safeProgress(percentage / 100),
                      minHeight: 9,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),

                  const SizedBox(height: 10),

                  Text(
                    'از ${faNumber(_safeLessonCount(report.adherenceSample))} '
                    'کار با موعد گذشته، '
                    '${faNumber(percentage.round())}٪ انجام شده است.',
                    style: const TextStyle(
                      height: 1.8,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Weekly study chart
  // ---------------------------------------------------------------------------

  Widget _buildWeeklySection(
    List<WeekLoad> weeks,
    int maxMinutes,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section('ساعت مطالعه چهار هفته اخیر'),

        if (weeks.isEmpty)
          const EmptyState(
            title: 'داده‌ای برای نمودار وجود ندارد',
            subtitle: 'با ثبت برنامه و انجام فعالیت‌های مطالعه، '
                'گزارش هفتگی نمایش داده می‌شود.',
            icon: Icons.bar_chart_outlined,
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  SizedBox(
                    height: 150,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (var i = 0; i < weeks.length; i++)
                          Expanded(
                            child: _weekColumn(
                              weeks[i],
                              i + 1,
                              maxMinutes,
                            ),
                          ),
                      ],
                    ),
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
                      _ChartLegend(
                        color: teal,
                        label: 'انجام‌شده',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _weekColumn(
    WeekLoad week,
    int number,
    int maxMinutes,
  ) {
    final planned = _safeLessonCount(week.plannedMinutes);
    final completed = _safeLessonCount(week.completedMinutes);

    double barHeight(int minutes) {
      if (minutes <= 0) return 2;

      return (minutes / maxMinutes * 110)
          .clamp(2.0, 110.0)
          .toDouble();
    }

    return Semantics(
      label: 'هفته ${faNumber(number)}',
      value: 'برنامه‌ریزی‌شده ${faNumber(planned)} دقیقه، '
          'انجام‌شده ${faNumber(completed)} دقیقه',
      child: ExcludeSemantics(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _bar(
                  barHeight(planned),
                  Colors.grey.shade400,
                ),
                const SizedBox(width: 4),
                _bar(
                  barHeight(completed),
                  teal,
                ),
              ],
            ),

            const SizedBox(height: 7),

            Text(
              'هفته ${faNumber(number)}',
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bar(double height, Color color) {
    return Container(
      width: 13,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Common UI helpers
  // ---------------------------------------------------------------------------

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _trendText(SubjectProgress progress) {
    final trend = progress.trend;

    if (trend == null || !trend.isFinite) {
      return '${faNumber(_safeLessonCount(progress.examCount))} '
          'نمره ثبت شده است؛ برای سنجش روند، حداقل دو نمره لازم است.';
    }

    if (trend >= 3) {
      return 'روند صعودی: آخرین نمره حدود '
          '${faNumber(trend.round())} واحد درصد بالاتر '
          'از میانگین قبلی است.';
    }

    if (trend <= -3) {
      return 'روند نزولی: آخرین نمره حدود '
          '${faNumber(trend.abs().round())} واحد درصد پایین‌تر '
          'از میانگین قبلی است.';
    }

    return 'روند نمرات تقریباً ثابت است.';
  }
}

/// Legend item for the weekly study chart.
class _ChartLegend extends StatelessWidget {
  const _ChartLegend({
    required this.color,
    required this.label,
  });

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
