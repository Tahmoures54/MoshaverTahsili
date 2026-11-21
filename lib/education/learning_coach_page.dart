import 'package:flutter/material.dart';

import 'education_store.dart';
import 'learning_engine.dart';
import 'ui.dart';

int _safeCoachMinutes(Object? value, {required int fallback}) {
  if (value is num && value.isFinite) {
    return value.round().clamp(0, 1440).toInt();
  }
  final parsed = int.tryParse(digitsToEnglish(value?.toString() ?? '').trim());
  return parsed == null ? fallback : parsed.clamp(0, 1440).toInt();
}

int _coachDayDifference(DateTime from, DateTime to) {
  // UTC calendar arithmetic avoids 23/25-hour daylight-saving days.
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

String _cleanCoachText(Object? value, {String fallback = '', int maxLength = 120}) {
  final text = value?.toString().trim() ?? '';
  if (text.isEmpty) return fallback;
  return text.length <= maxLength ? text : '${text.substring(0, maxLength - 1)}…';
}

/// A transparent coaching layer built only from records already stored locally.
/// It is a planning aid, not an assessment of ability, motivation or health.
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
      case 'starter':
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
/// 1. Nearest exam (0–3 calendar days)
/// 2. Oldest overdue task (shorter task breaks ties)
/// 3. Weak subject with at least two valid scored exams
/// 4. Due flashcards
/// 5. Gentle starter when the evidence is sparse
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
  final cap = dailyMinutes.clamp(15, 240).toInt();

  // Accept older records with date-time values as well as current yyyy-MM-dd keys.
  final todayLoad = tasks.fold<int>(0, (sum, task) {
    if (task['done'] == true || parseDay(task['dueDate']) == null ||
        isoDay(parseDay(task['dueDate'])!) != todayKey) {
      return sum;
    }
    final minutes = _safeCoachMinutes(task['minutes'], fallback: 0);
    return (sum + minutes).clamp(0, 1000000000).toInt();
  });
  final available = (cap - todayLoad).clamp(0, cap).toInt();
  final candidates = <LearningCoachStep>[];
  final notes = <String>[];

  final validExams = exams.where((exam) => examPercent(exam) != null).toList();
  final examCounts = <String, int>{};
  for (final exam in validExams) {
    final subject = _cleanCoachText(exam['subject'], maxLength: 100);
    if (subject.isNotEmpty) {
      examCounts[subject] = (examCounts[subject] ?? 0) + 1;
    }
  }
  if (validExams.isEmpty) {
    notes.add('برای پیشنهاد دقیق‌تر، نتیجه یک آزمون معتبر را ثبت کن.');
  } else if (validExams.length < 3) {
    notes.add('تعداد نمره‌های ثبت‌شده هنوز کم است؛ پیشنهادهای درسی مقدماتی‌اند.');
  }

  // 1. Nearest upcoming exam. Ignore malformed or subject-less records.
  final upcoming = deadlines
      .map((item) => (item: item, date: parseDay(item['date'])))
      .where((entry) => entry.date != null)
      .where((entry) => _cleanCoachText(entry.item['subject']).isNotEmpty)
      .where((entry) {
        final days = _coachDayDifference(today, entry.date!);
        return days >= 0 && days <= 3;
      }).toList()
    ..sort((a, b) => a.date!.compareTo(b.date!));

  if (upcoming.isNotEmpty) {
    final exam = upcoming.first;
    final subject = _cleanCoachText(exam.item['subject'], maxLength: 100);
    final daysLeft = _coachDayDifference(today, exam.date!);
    final when = switch (daysLeft) {
      0 => 'امروز',
      1 => 'فردا',
      _ => 'تا ${toPersianDigits(daysLeft)} روز دیگر',
    };
    candidates.add(LearningCoachStep(
      title: 'مرور هدفمند برای امتحان $subject',
      subject: subject,
      minutes: 20,
      kind: 'deadline',
      reason: 'امتحان این درس $when است؛ یک مرور کوتاه و چند سؤال نمونه انجام بده.',
    ));
  }

  // 2. Overdue tasks: oldest first, then shortest. Invalid dates are ignored.
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

  if (overdue.isNotEmpty) {
    final task = overdue.first;
    final title = _cleanCoachText(task['title'], fallback: 'کار عقب‌افتاده');
    final subject = _cleanCoachText(task['subject'], fallback: 'عمومی', maxLength: 100);
    candidates.add(LearningCoachStep(
      title: 'شروع دوباره: $title',
      subject: subject,
      minutes: 15,
      kind: 'overdue',
      reason: 'به‌جای جبران همه عقب‌ماندگی در یک روز، فقط ۱۵ دقیقه روی قدم اول این کار تمرکز کن.',
    ));
  }

  // 3. A low score from one exam is not enough to label a subject as weak.
  final averages = subjectAverages(validExams);
  final weakSubjects = averages.entries
      .where((entry) => entry.value < 60 && (examCounts[entry.key] ?? 0) >= 2)
      .toList()
    ..sort((a, b) {
      final byAverage = a.value.compareTo(b.value);
      return byAverage != 0 ? byAverage : a.key.compareTo(b.key);
    });

  if (weakSubjects.isNotEmpty) {
    final weak = weakSubjects.first;
    candidates.add(LearningCoachStep(
      title: 'تمرین مفهومی ${weak.key}',
      subject: weak.key,
      minutes: 20,
      kind: 'practice',
      reason: 'میانگین دو یا چند آزمون ثبت‌شده در این درس کمتر از ۶۰٪ است؛ یک مفهوم مشخص را مرور کن و سپس چند سؤال حل کن.',
    ));
  }

  // 4. Active recall is suggested only when at least one card is due.
  final dueCards = cards.where((card) => isCardDue(card, now)).length;
  if (dueCards > 0) {
    candidates.add(LearningCoachStep(
      title: 'مرور فلش‌کارت‌های سررسیدشده',
      subject: 'مرور',
      minutes: 10,
      kind: 'retrieval',
      reason: '${toPersianDigits(dueCards)} فلش‌کارت برای بازیابی فعال آماده است؛ پاسخ را پیش از دیدن پشت کارت به یاد بیاور.',
    ));
  }

  // 5. A small, non-judgmental starter when no higher-priority signal exists.
  if (candidates.isEmpty) {
    final hasOpenTasks = tasks.any((task) => task['done'] != true);
    candidates.add(LearningCoachStep(
      title: hasOpenTasks ? 'یک کار کوچک از برنامه‌ات' : 'یک نوبت یادآوری فعال',
      subject: 'عمومی',
      minutes: 15,
      kind: 'starter',
      reason: hasOpenTasks
          ? 'یکی از کارهای باز را انتخاب کن و فقط ۱۵ دقیقه روی آن کار کن. لازم نیست همه کارها را یک‌باره تمام کنی.'
          : 'یک بخش کوتاه را بخوان، کتاب را ببند و نکته‌های اصلی را از حافظه بنویس؛ سپس پاسخ خودت را بررسی کن.',
    ));
  }

  final unique = <String>{};
  final filtered = <LearningCoachStep>[];
  var remainingMinutes = available;
  var duplicateCount = 0;
  var budgetBlockedCount = 0;

  for (final step in candidates) {
    if (filtered.length == 3) break;
    final key = '${step.kind}|${step.subject}|${step.title}';
    if (!unique.add(key)) continue;

    final alreadyOpen = tasks.any((task) =>
        task['done'] != true &&
        _cleanCoachText(task['title']) == step.title &&
        parseDay(task['dueDate']) != null &&
        isoDay(parseDay(task['dueDate'])!) == todayKey);
    if (alreadyOpen) {
      duplicateCount++;
      continue;
    }

    if (step.minutes > remainingMinutes) {
      budgetBlockedCount++;
      continue;
    }

    filtered.add(step);
    remainingMinutes -= step.minutes;
  }

  if (filtered.isEmpty && budgetBlockedCount > 0) {
    notes.add('ظرفیت آزاد امروز برای پیشنهادهای باقی‌مانده کافی نیست؛ می‌توانی آن‌ها را برای روز دیگری برنامه‌ریزی کنی.');
  } else if (filtered.isEmpty && duplicateCount > 0) {
    notes.add('قدم‌های پیشنهادی قبلاً در برنامه امروزت ثبت شده‌اند. همان‌ها را ادامه بده.');
  }

  return LearningCoachPlan(
    steps: List.unmodifiable(filtered),
    availableMinutes: available,
    plannedMinutes: todayLoad,
    evidenceNotes: List.unmodifiable(notes),
  );
}

int _coachIdSequence = 0;

String _newCoachTaskId() {
  _coachIdSequence++;
  return 'coach-${DateTime.now().microsecondsSinceEpoch}-$_coachIdSequence';
}

class LearningCoachPage extends StatefulWidget {
  const LearningCoachPage({super.key, required this.store});
  final EducationStore store;

  @override
  State<LearningCoachPage> createState() => _LearningCoachPageState();
}

class _LearningCoachPageState extends State<LearningCoachPage> {
  final Set<String> saving = <String>{};

  String _key(LearningCoachStep step) => '${step.kind}|${step.subject}|${step.title}';

  int _dailyMinutes(Map<String, dynamic>? profile) {
    final value = profile?['dailyMinutes'];
    if (value is num && value.isFinite) return value.round().clamp(15, 240).toInt();
    final parsed = int.tryParse(digitsToEnglish(value?.toString() ?? '').trim());
    return (parsed ?? 120).clamp(15, 240).toInt();
  }

  Future<void> _addStep(LearningCoachStep step) async {
    final key = _key(step);
    if (saving.contains(key)) return;

    // Re-check the current store immediately before writing. The displayed plan
    // may have become stale while the user was reading it or another save ran.
    final now = DateTime.now();
    final tasks = widget.store.tasks;
    final todayKey = isoDay(now);
    final duplicate = tasks.any((task) =>
        task['done'] != true &&
        _cleanCoachText(task['title']) == step.title &&
        parseDay(task['dueDate']) != null &&
        isoDay(parseDay(task['dueDate'])!) == todayKey);
    if (duplicate) {
      showMessage(context, 'این قدم از قبل در برنامه امروزت وجود دارد.');
      return;
    }

    final dailyMinutes = _dailyMinutes(widget.store.profile);
    final planned = tasks.fold<int>(0, (sum, task) {
      if (task['done'] == true || parseDay(task['dueDate']) == null ||
          isoDay(parseDay(task['dueDate'])!) != todayKey) {
        return sum;
      }
      return (sum + _safeCoachMinutes(task['minutes'], fallback: 0))
          .clamp(0, 1000000000).toInt();
    });
    if (planned + step.minutes > dailyMinutes) {
      showMessage(context, 'ظرفیت زمانی امروز تغییر کرده است؛ برنامه را دوباره بررسی کن.');
      return;
    }

    setState(() => saving.add(key));
    try {
      await widget.store.addTask({
        'id': _newCoachTaskId(),
        'title': step.title,
        'subject': step.subject,
        'minutes': step.minutes,
        'done': false,
        'dueDate': todayKey,
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
          final dailyMinutes = _dailyMinutes(widget.store.profile);
          final tasks = widget.store.tasks;
          final plan = buildLearningCoachPlan(
            exams: widget.store.exams,
            tasks: tasks,
            cards: widget.store.cards,
            deadlines: widget.store.deadlines,
            now: DateTime.now(),
            dailyMinutes: dailyMinutes,
          );
          final progress = (plan.plannedMinutes / dailyMinutes).clamp(0.0, 1.0);

          return Scaffold(
            appBar: AppBar(title: const Text('مربی یادگیری من')),
            body: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'قدم بعدی را هوشمندانه انتخاب کنیم',
                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'این پیشنهادها فقط از نمره‌ها، برنامه‌ها، امتحان‌ها و مرورهای ثبت‌شده روی همین گوشی ساخته می‌شوند.',
                        ),
                        const SizedBox(height: 12),
                        Text('زمان برنامه‌ریزی‌شده امروز: ${faNumber(plan.plannedMinutes)} دقیقه'),
                        Text('ظرفیت آزاد امروز: ${faNumber(plan.availableMinutes)} دقیقه از ${faNumber(dailyMinutes)} دقیقه'),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: progress),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                for (final note in plan.evidenceNotes)
                  NoticeCard(text: note, warning: true),
                if (plan.steps.isEmpty)
                  EmptyState(
                    title: plan.availableMinutes == 0 ? 'ظرفیت امروز تکمیل شده است' : 'فعلاً قدم تازه‌ای لازم نیست',
                    subtitle: plan.availableMinutes == 0
                        ? 'برنامه امروزت به سقف زمانی رسیده است. استراحت هم بخشی از یادگیری است.'
                        : 'قدم‌های پیشنهادی در برنامه‌ات ثبت شده‌اند یا داده تازه‌ای برای پیشنهاد وجود ندارد.',
                    icon: Icons.check_circle_outline,
                  ),
                for (final step in plan.steps)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.auto_awesome, color: teal),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  step.title,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(step.reason, style: const TextStyle(height: 1.7)),
                          const SizedBox(height: 8),
                          Text(
                            '${step.subject} · ${faNumber(step.minutes)} دقیقه',
                            style: const TextStyle(color: Colors.blueGrey, fontSize: 12),
                          ),
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
                        ],
                      ),
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
