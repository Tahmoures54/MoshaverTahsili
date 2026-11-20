import 'package:flutter/material.dart';

import 'education_store.dart';
import 'learning_engine.dart';
import 'ui.dart';

int _safeCoachMinutes(Object? value, {required int fallback}) {
  if (value is num && value.isFinite) return value.round().clamp(0, 1440).toInt();
  final parsed = int.tryParse(digitsToEnglish(value?.toString() ?? ''));
  return parsed == null ? fallback : parsed.clamp(0, 1440).toInt();
}

/// A transparent coaching layer built only from records already stored locally.
class LearningCoachStep {
  const LearningCoachStep({
    required this.title,
    required this.subject,
    required this.minutes,
    required this.reason,
    required this.kind,
  });

  final String title;
  final String subject;
  final int minutes;
  final String reason;
  final String kind;

  /// Navigation target on the main bottom bar: 1=planner, 2=exams, 3=cards, 4=advisor.
  int get preferredTab {
    switch (kind) {
      case 'retrieval':
        return 3;
      case 'practice':
      case 'deadline':
      case 'overdue':
        return 1;
      default:
        return 1;
    }
  }
}

class LearningCoachPlan {
  const LearningCoachPlan({
    required this.steps,
    required this.availableMinutes,
    required this.plannedMinutes,
    required this.evidenceNotes,
  });

  final List<LearningCoachStep> steps;
  final int availableMinutes;
  final int plannedMinutes;
  final List<String> evidenceNotes;

  /// The single most important next action, or null when nothing useful remains.
  LearningCoachStep? get primary => steps.isEmpty ? null : steps.first;
}

/// Returns up to three practical next steps. Thin evidence is never a diagnosis.
///
/// Ranking priority (highest first):
/// 1. Near exam (0–3 days)
/// 2. Overdue task (oldest / shortest first)
/// 3. Weak subject with enough evidence
/// 4. Due flashcards
/// 5. Gentle starter when data is sparse
LearningCoachPlan buildLearningCoachPlan({
  required List<Entry> exams,
  required List<Entry> tasks,
  required List<Entry> cards,
  required List<Entry> deadlines,
  required DateTime now,
  int dailyMinutes = 120,
}) {
  final today = startOfDay(now);
  final todayKey = isoDay(today);
  final cap = dailyMinutes.clamp(15, 240);
  final todayLoad = tasks.where((task) =>
      task['done'] != true && task['dueDate']?.toString() == todayKey)
      .fold<int>(0, (sum, task) {
        return sum + _safeCoachMinutes(task['minutes'], fallback: 0);
      });
  final available = (cap - todayLoad).clamp(0, cap).toInt();
  final steps = <LearningCoachStep>[];
  final notes = <String>[];

  final validExams = exams.where((exam) => examPercent(exam) != null).toList();
  final examCounts = <String, int>{};
  for (final exam in validExams) {
    final subject = exam['subject']?.toString().trim() ?? '';
    if (subject.isNotEmpty) examCounts[subject] = (examCounts[subject] ?? 0) + 1;
  }
  if (validExams.isEmpty) {
    notes.add('برای پیشنهاد دقیق‌تر، نتیجه یک آزمون را ثبت کن.');
  } else if (validExams.length < 3) {
    notes.add('تعداد نمره‌ها هنوز کم است؛ پیشنهادهای درسی مقدماتی‌اند.');
  }

  // 1. Near exams (highest priority)
  final upcoming = deadlines
      .map((item) => (item: item, date: parseDay(item['date'])))
      .where((entry) => entry.date != null)
      .where((entry) {
        final days = entry.date!.difference(today).inDays;
        return days >= 0 && days <= 3;
      }).toList()
    ..sort((a, b) => a.date!.compareTo(b.date!));
  if (upcoming.isNotEmpty) {
    final subject = upcoming.first.item['subject']?.toString().trim() ?? '';
    final daysLeft = upcoming.first.date!.difference(today).inDays;
    if (subject.isNotEmpty) {
      final when = daysLeft == 0
          ? 'امروز'
          : daysLeft == 1
              ? 'فردا'
              : 'تا ${toPersianDigits(daysLeft)} روز دیگر';
      steps.add(LearningCoachStep(
        title: 'مرور هدفمند برای امتحان $subject',
        subject: subject,
        minutes: 20,
        kind: 'deadline',
        reason: 'امتحان این درس $when است؛ یک مرور کوتاه و چند سؤال نمونه انجام بده.',
      ));
    }
  }

  // 2. Overdue tasks
  final overdue = tasks.where((task) {
    final due = parseDay(task['dueDate']);
    return task['done'] != true && due != null && due.isBefore(today);
  }).toList()
    ..sort((a, b) {
      final aDate = parseDay(a['dueDate'])!;
      final bDate = parseDay(b['dueDate'])!;
      final dateOrder = aDate.compareTo(bDate);
      if (dateOrder != 0) return dateOrder;
      return _safeCoachMinutes(a['minutes'], fallback: 30)
          .compareTo(_safeCoachMinutes(b['minutes'], fallback: 30));
    });
  if (overdue.isNotEmpty && steps.length < 3) {
    final task = overdue.first;
    final title = task['title']?.toString().trim() ?? 'کار عقب‌افتاده';
    final subject = task['subject']?.toString().trim() ?? 'عمومی';
    steps.add(LearningCoachStep(
      title: 'شروع دوباره: $title',
      subject: subject,
      minutes: 15,
      kind: 'overdue',
      reason: 'به‌جای جبران همه عقب‌ماندگی در یک روز، فقط ۱۵ دقیقه روی قدم اول این کار تمرکز کن.',
    ));
  }

  // 3. Weak subjects (need at least two scored exams)
  final averages = subjectAverages(validExams);
  final weakSubjects = averages.entries
      .where((entry) => entry.value < 60 && (examCounts[entry.key] ?? 0) >= 2)
      .toList()
    ..sort((a, b) => a.value.compareTo(b.value));
  if (weakSubjects.isNotEmpty && steps.length < 3) {
    final weak = weakSubjects.first;
    steps.add(LearningCoachStep(
      title: 'تمرین مفهومی ${weak.key}',
      subject: weak.key,
      minutes: 20,
      kind: 'practice',
      reason: 'میانگین دو یا چند آزمون ثبت‌شده در این درس کمتر از ۶۰٪ است؛ یک مفهوم مشخص را مرور کن و سپس چند سؤال حل کن.',
    ));
  }

  // 4. Due flashcards
  final dueCards = cards.where((card) => isCardDue(card, now)).length;
  if (dueCards > 0 && steps.length < 3) {
    steps.add(LearningCoachStep(
      title: 'مرور فلش‌کارت‌های سررسیدشده',
      subject: 'مرور',
      minutes: 10,
      kind: 'retrieval',
      reason: '${toPersianDigits(dueCards)} فلش‌کارت برای بازیابی فعال آماده است؛ پاسخ را قبل از دیدن پشت کارت به یاد بیاور.',
    ));
  }

  // 5. Gentle starter when nothing else is available
  if (steps.isEmpty) {
    final hasAnyTasks = tasks.any((task) => task['done'] != true);
    if (hasAnyTasks) {
      steps.add(const LearningCoachStep(
        title: 'یک کار کوچک از برنامه امروز',
        subject: 'عمومی',
        minutes: 15,
        kind: 'starter',
        reason: 'یکی از کارهای باز را انتخاب کن و فقط ۱۵ دقیقه روی آن کار کن. تمام‌کردن یک کار کوچک بهتر از شروع چند کار ناتمام است.',
      ));
    } else {
      steps.add(const LearningCoachStep(
        title: 'یک نوبت یادآوری فعال',
        subject: 'عمومی',
        minutes: 15,
        kind: 'starter',
        reason: 'یک بخش کوتاه را بخوان، کتاب را ببند و نکته‌های اصلی را از حافظه بنویس؛ بعد پاسخ خودت را بررسی کن.',
      ));
    }
  }

  final unique = <String>{};
  final filtered = steps.where((step) {
    // Never recommend a step that cannot fit into the learner's remaining time.
    if (step.minutes > available) return false;
    final key = '${step.kind}|${step.subject}|${step.title}';
    if (!unique.add(key)) return false;
    final alreadyOpen = tasks.any((task) =>
        task['done'] != true &&
        task['title']?.toString().trim() == step.title &&
        task['dueDate']?.toString() == todayKey);
    return !alreadyOpen;
  }).take(3).toList();

  return LearningCoachPlan(
    steps: filtered,
    availableMinutes: available,
    plannedMinutes: todayLoad,
    evidenceNotes: notes,
  );
}

class LearningCoachPage extends StatefulWidget {
  const LearningCoachPage({super.key, required this.store});
  final EducationStore store;

  @override
  State<LearningCoachPage> createState() => _LearningCoachPageState();
}

class _LearningCoachPageState extends State<LearningCoachPage> {
  final Set<String> saving = {};

  String _key(LearningCoachStep step) => '${step.kind}|${step.subject}|${step.title}';

  Future<void> _addStep(LearningCoachStep step) async {
    final key = _key(step);
    if (saving.contains(key)) return;
    setState(() => saving.add(key));
    try {
      await widget.store.addTask({
        'id': 'coach-${DateTime.now().microsecondsSinceEpoch}',
        'title': step.title,
        'subject': step.subject,
        'minutes': step.minutes,
        'done': false,
        'dueDate': isoDay(DateTime.now()),
        'createdAt': DateTime.now().toIso8601String(),
        'source': 'personal_learning_coach_v1',
      });
      if (mounted) showMessage(context, 'این قدم به برنامه امروز اضافه شد.');
    } on Object catch (error) {
      if (mounted) showMessage(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => saving.remove(key));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final profile = widget.store.profile ?? {};
      final dailyValue = profile['dailyMinutes'];
      final dailyMinutes = dailyValue is int ? dailyValue : 120;
      final plan = buildLearningCoachPlan(
        exams: widget.store.exams,
        tasks: widget.store.tasks,
        cards: widget.store.cards,
        deadlines: widget.store.deadlines,
        now: DateTime.now(),
        dailyMinutes: dailyMinutes,
      );
      return Scaffold(
        appBar: AppBar(title: const Text('مربی یادگیری من')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('قدم بعدی را هوشمندانه انتخاب کنیم',
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('این پیشنهادها فقط از نمره‌ها، برنامه‌ها، امتحان‌ها و مرورهای ثبت‌شده روی همین گوشی ساخته می‌شوند.'),
                  const SizedBox(height: 12),
                  Text('ظرفیت آزاد امروز: ${faNumber(plan.availableMinutes)} دقیقه از ${faNumber(dailyMinutes)} دقیقه'),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    value: dailyMinutes <= 0 ? 0.0 : (plan.plannedMinutes / dailyMinutes).clamp(0.0, 1.0),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            for (final note in plan.evidenceNotes)
              NoticeCard(text: note, warning: true),
            if (plan.steps.isEmpty)
              const EmptyState(title: 'قدم بعدی ثبت شد', subtitle: 'برای دریافت پیشنهاد تازه، برنامه یا نتیجه آزمونت را به‌روزرسانی کن.', icon: Icons.check_circle_outline),
            for (final step in plan.steps)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.auto_awesome, color: teal),
                      const SizedBox(width: 8),
                      Expanded(child: Text(step.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                    ]),
                    const SizedBox(height: 8),
                    Text(step.reason, style: const TextStyle(height: 1.7)),
                    const SizedBox(height: 8),
                    Text('${step.subject} · ${faNumber(step.minutes)} دقیقه',
                        style: const TextStyle(color: Colors.blueGrey, fontSize: 12)),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        onPressed: saving.contains(_key(step)) || plan.availableMinutes < step.minutes
                            ? null
                            : () => _addStep(step),
                        icon: const Icon(Icons.add_task),
                        label: Text(saving.contains(_key(step)) ? 'در حال افزودن…' : 'افزودن به برنامه امروز'),
                      ),
                    ),
                  ]),
                ),
              ),
            const NoticeCard(
              text: 'این ابزار مربی برنامه‌ریزی است، نه آزمون استعداد یا تشخیص روان‌شناختی. با داده کم، پیشنهادها مقدماتی‌اند. اگر ظرفیت امروز کافی نیست، برنامه را سبک‌تر کن؛ لازم نیست برای جبران، بیش از توانت درس بخوانی.',
              icon: Icons.info_outline,
            ),
          ],
        ),
      );
    },
  );
}
