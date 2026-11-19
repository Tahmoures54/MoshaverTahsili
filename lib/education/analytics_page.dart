import 'package:flutter/material.dart';

import 'education_store.dart';
import 'learning_engine.dart';
import 'mastery_estimator.dart';
import 'ui.dart';

/// Local performance analytics. Every figure comes from the student's own
/// records; a missing record is reported as a gap, never filled with a guess.
class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key, required this.store});
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
    var maxMinutes = 1;
    for (final week in report.weeks) {
      if (week.plannedMinutes > maxMinutes) maxMinutes = week.plannedMinutes;
      if (week.completedMinutes > maxMinutes) maxMinutes = week.completedMinutes;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('تحلیل عملکرد تحصیلی')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const NoticeCard(
          text: 'این تحلیل فقط از داده‌های ثبت‌شده خودت ساخته می‌شود و روی گوشی می‌ماند. '
              'نتیجه‌ها نشانه‌هایی برای تصمیم‌گیری‌اند، نه حکم قطعی.',
          icon: Icons.insights_outlined,
        ),
        for (final gap in report.dataGaps) NoticeCard(text: gap, warning: true),
        if (report.strengths.isNotEmpty)
          NoticeCard(
            text: 'نقاط قوت: ${report.strengths.map((s) => s.subject).join('، ')}',
            icon: Icons.emoji_events_outlined,
          ),
        if (report.weaknesses.isNotEmpty)
          NoticeCard(
            text: 'نیازمند تمرین بیشتر: ${report.weaknesses.map((s) => s.subject).join('، ')}',
            warning: true,
          ),
        _section('میانگین درس‌ها'),
        if (report.subjects.isEmpty)
          const EmptyState(
            title: 'هنوز داده‌ای نداریم',
            subtitle: 'با ثبت نمره آزمون، میانگین و روند هر درس نمایش داده می‌شود.',
            icon: Icons.assessment_outlined,
          ),
        for (final subject in report.subjects)
          Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(child: Text(subject.subject, style: const TextStyle(fontWeight: FontWeight.bold))),
                Text('${faNumber(subject.average.toStringAsFixed(1))}٪',
                    style: const TextStyle(color: blue, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: subject.average / 100, minHeight: 7, borderRadius: BorderRadius.circular(8)),
              const SizedBox(height: 6),
              Text(_trendText(subject), style: const TextStyle(fontSize: 13, height: 1.6)),
            ],
          ))),
        _section('شواهد یادگیری به تفکیک مبحث'),
        if (topicMastery.isEmpty)
          const EmptyState(
            title: 'هنوز شواهد موضوعی ثبت نشده',
            subtitle: 'برای هر فلش‌کارت، نام مبحث را ثبت کن و پس از مرور، نتیجه یادآوری را ارزیابی کن.',
            icon: Icons.school_outlined,
          ),
        for (final item in topicMastery)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(item.topic, style: const TextStyle(fontWeight: FontWeight.bold))),
                      Text('${faNumber((item.estimate * 100).round())}٪',
                          style: const TextStyle(color: blue, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: item.estimate, minHeight: 7),
                  const SizedBox(height: 6),
                  Text(
                    '${item.confidence} · ${faNumber(item.evidenceCount)} مرور ثبت‌شده · بازه برآورد ${faNumber((item.lowerBound * 100).round())} تا ${faNumber((item.upperBound * 100).round())} درصد',
                    style: const TextStyle(fontSize: 12, height: 1.6),
                  ),
                ],
              ),
            ),
          ),
        const NoticeCard(
          text: 'این درصد، برآورد محافظه‌کارانه از سابقه یادآوری فلش‌کارت‌هاست؛ نمره امتحان یا احتمال قطعی موفقیت نیست. شواهد بیشتر، برآورد را قابل اتکاتر می‌کند.',
          icon: Icons.info_outline,
        ),
        _section('پایبندی به برنامه'),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(
          report.adherence == null
              ? 'هنوز کار با موعد گذشته‌ای برای سنجش نداریم.'
              : 'از ${faNumber(report.adherenceSample)} کار با موعد گذشته، '
                  '${faNumber((report.adherence! * 100).round())}٪ انجام شده است.',
          style: const TextStyle(height: 1.7),
        ))),
        _section('ساعت مطالعه چهار هفته اخیر'),
        Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
          SizedBox(height: 150, child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var i = 0; i < report.weeks.length; i++)
                Expanded(child: _weekColumn(report.weeks[i], i + 1, maxMinutes)),
            ],
          )),
          const SizedBox(height: 10),
          const Text('میله خاکستری: برنامه‌ریزی‌شده · میله سبز: انجام‌شده',
              style: TextStyle(fontSize: 12.5)),
        ]))),
      ]),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
      );

  Widget _weekColumn(WeekLoad week, int number, int maxMinutes) {
    double height(int minutes) => minutes <= 0 ? 2.0 : (minutes / maxMinutes * 110).clamp(2.0, 110.0).toDouble();
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _bar(height(week.plannedMinutes), Colors.grey.shade400),
            const SizedBox(width: 4),
            _bar(height(week.completedMinutes), teal),
          ],
        ),
        const SizedBox(height: 6),
        Text('هفته ${faNumber(number)}', style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _bar(double height, Color color) => Container(
        width: 12,
        height: height,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      );

  String _trendText(SubjectProgress progress) {
    final trend = progress.trend;
    if (trend == null) {
      return '${faNumber(progress.examCount)} نمره ثبت شده است؛ برای سنجش روند، حداقل دو نمره لازم است.';
    }
    if (trend >= 3) {
      return 'روند صعودی: آخرین نمره حدود ${faNumber(trend.round())} درصد بالاتر از میانگین قبلی است.';
    }
    if (trend <= -3) {
      return 'روند نزولی: آخرین نمره حدود ${faNumber(trend.abs().round())} درصد پایین‌تر از میانگین قبلی است.';
    }
    return 'روند تقریباً ثابت است.';
  }
}
