import 'package:flutter/material.dart';

import 'education_store.dart';
import 'learning_engine.dart';
import 'ui.dart';

const _coachRelevantKeys = <String>[
  'edu.profile',
  'edu.exams',
  'edu.tasks',
  'edu.cards',
  'edu.deadlines',
];

int _safeCoachMinutes(Object? value, {required int fallback}) {
  if (value is num && value.isFinite) {
    return value.clamp(0, 1440).round();
  }

  final parsed = int.tryParse(digitsToEnglish(value?.toString() ?? '').trim());

  return (parsed ?? fallback).clamp(0, 1440).toInt();
}

int _coachDailyMinutes(Map<String, dynamic>? profile) {
  final value = profile?['dailyMinutes'];

  if (value is num && value.isFinite) {
    return value.clamp(15, 240).round();
  }

  final parsed = int.tryParse(digitsToEnglish(value?.toString() ?? '').trim());

  return (parsed ?? 120).clamp(15, 240).toInt();
}

/// UTC calendar arithmetic avoids 23/25-hour daylight-saving days.
int _coachDayDifference(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);

  return b.difference(a).inDays;
}

String _cleanCoachText(
  Object? value, {
  String fallback = '',
  int maxLength = 120,
}) {
  if (maxLength <= 0) return '';

  final text = (value?.toString() ?? '')
      .replaceAll(
        RegExp(
          r'[\u0000-\u001F\u007F-\u009F'
          r'\u061C\u200E\u200F\u202A-\u202E'
          r'\u2066-\u2069\u2028\u2029\uFEFF]',
        ),
        ' ',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  if (text.isEmpty) return fallback;

  final codePoints = text.runes.toList(growable: false);

  if (codePoints.length <= maxLength) return text;
  if (maxLength == 1) return '…';

  return '${String.fromCharCodes(codePoints.take(maxLength - 1))}…';
}

String _coachStepKey(LearningCoachStep step) {
  // Length prefixes prevent separator characters in user labels
  // from creating ambiguous keys.
  return '${step.kind.length}:${step.kind}'
      '${step.subject.length}:${step.subject}'
      '${step.title.length}:${step.title}';
}

bool _coachTaskIsOnDay(Entry task, DateTime day) {
  final due = parseDay(task['dueDate']);

  return due != null && _coachDayDifference(day, due) == 0;
}

int _coachOpenMinutesOnDay(List<Entry> tasks, DateTime day) {
  return tasks.fold<int>(0, (sum, task) {
    if (task['done'] == true || !_coachTaskIsOnDay(task, day)) {
      return sum;
    }

    return (sum + _safeCoachMinutes(task['minutes'], fallback: 0))
        .clamp(0, 1000000000)
        .toInt();
  });
}

bool _coachAlreadyScheduled(
  List<Entry> tasks,
  LearningCoachStep step,
  DateTime day,
) {
  final title = _cleanCoachText(step.title, maxLength: 240);

  return tasks.any(
    (task) =>
        task['done'] != true &&
        _coachTaskIsOnDay(task, day) &&
        _cleanCoachText(task['title'], maxLength: 240) == title,
  );
}

/// Local, transparent planning advice.
///
/// This is not an assessment of ability, motivation or health.
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

  /// Main bottom-bar target:
  /// 1=planner, 2=exams, 3=cards, 4=advisor.
  int get preferredTab {
    switch (kind) {
      case 'retrieval':
        return 3;
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

  /// Additional capacity after subtracting today's unfinished tasks.
  final int availableMinutes;

  /// Recorded duration of today's unfinished tasks, not actual study time.
  ///
  /// Field name retained for compatibility.
  final int plannedMinutes;

  final List<String> evidenceNotes;

  LearningCoachStep? get primary => steps.isEmpty ? null : steps.first;
}

/// Returns up to three practical next steps.
///
/// Priority:
/// 1. Nearest exam within 0–3 calendar days.
/// 2. Oldest overdue task; shorter duration breaks ties.
/// 3. Subject average below 60%, with at least two valid scored exams.
/// 4. Due flashcards.
/// 5. Gentle starter when no higher-priority signal exists.
///
/// Time capacity is based on unfinished tasks scheduled for today.
/// It does not measure actual time spent studying.
LearningCoachPlan buildLearningCoachPlan({
  required List<Entry> exams,
  required List<Entry> tasks,
  required List<Entry> cards,
  required List<Entry> deadlines,
  required DateTime now,
  int dailyMinutes = 120,
}) {
  final today = startOfDay(now);
  final cap = dailyMinutes.clamp(15, 240).toInt();

  final todayLoad = _coachOpenMinutesOnDay(tasks, today);
  final available = (cap - todayLoad).clamp(0, cap).toInt();

  final candidates = <LearningCoachStep>[];
  final notes = <String>[];

  // Use the SAME normalized subject in counts and averages.
  // Otherwise spaces or truncation can make their keys disagree.
  final validExams = <Entry>[];
  var invalidExamCount = 0;
  var missingExamSubjectCount = 0;

  for (final exam in exams) {
    final percent = examPercent(exam);

    if (percent == null || !percent.isFinite || percent < 0 || percent > 100) {
      invalidExamCount++;
      continue;
    }

    final subject = _cleanCoachText(exam['subject'], maxLength: 100);

    if (subject.isEmpty) {
      missingExamSubjectCount++;
      continue;
    }

    validExams.add({...exam, 'subject': subject});
  }

  final examCounts = <String, int>{};

  for (final exam in validExams) {
    final subject = exam['subject'] as String;
    examCounts[subject] = (examCounts[subject] ?? 0) + 1;
  }

  if (validExams.isEmpty) {
    notes.add(
      'برای پیشنهاد درسی دقیق‌تر، '
      'نتیجه یک آزمون معتبر همراه با نام درس ثبت کن.',
    );
  } else if (validExams.length < 3) {
    notes.add(
      'تعداد نمره‌های ثبت‌شده هنوز کم است؛ '
      'پیشنهادهای درسی مقدماتی‌اند.',
    );
  }

  if (invalidExamCount > 0) {
    notes.add(
      '${faNumber(invalidExamCount)} نتیجه آزمون '
      'نمره قابل محاسبه ندارد و در پیشنهاد درسی استفاده نشده است.',
    );
  }

  if (missingExamSubjectCount > 0) {
    notes.add(
      '${faNumber(missingExamSubjectCount)} نتیجه آزمون '
      'نام درس ندارد و در پیشنهاد درسی استفاده نشده است.',
    );
  }

  final invalidTaskDates = tasks
      .where(
        (task) => task['done'] != true && parseDay(task['dueDate']) == null,
      )
      .length;

  if (invalidTaskDates > 0) {
    notes.add(
      '${faNumber(invalidTaskDates)} کار باز، '
      'موعد قابل خواندن ندارد؛ '
      'در ظرفیت امروز و تشخیص عقب‌افتادگی محاسبه نشده است.',
    );
  }

  // 1. Nearest upcoming exam.
  final upcoming =
      deadlines.map((item) => (item: item, date: parseDay(item['date']))).where(
        (entry) {
          final date = entry.date;
          if (date == null) return false;

          if (_cleanCoachText(entry.item['subject'], maxLength: 100).isEmpty) {
            return false;
          }

          final days = _coachDayDifference(today, date);
          return days >= 0 && days <= 3;
        },
      ).toList()..sort((a, b) {
        final dateOrder = a.date!.compareTo(b.date!);
        if (dateOrder != 0) return dateOrder;

        return _cleanCoachText(
          a.item['subject'],
          maxLength: 100,
        ).compareTo(_cleanCoachText(b.item['subject'], maxLength: 100));
      });

  final invalidDeadlines = deadlines
      .where(
        (item) =>
            parseDay(item['date']) == null ||
            _cleanCoachText(item['subject'], maxLength: 100).isEmpty,
      )
      .length;

  if (invalidDeadlines > 0) {
    notes.add(
      '${faNumber(invalidDeadlines)} موعد امتحان '
      'تاریخ معتبر یا نام درس ندارد '
      'و در اولویت‌بندی امتحان‌ها استفاده نشده است.',
    );
  }

  if (upcoming.isNotEmpty) {
    final exam = upcoming.first;

    final subject = _cleanCoachText(exam.item['subject'], maxLength: 100);

    final daysLeft = _coachDayDifference(today, exam.date!);

    final when = switch (daysLeft) {
      0 => 'امروز',
      1 => 'فردا',
      _ => 'تا ${toPersianDigits(daysLeft)} روز دیگر',
    };

    candidates.add(
      LearningCoachStep(
        title: 'مرور هدفمند برای امتحان $subject',
        subject: subject,
        minutes: 20,
        kind: 'deadline',
        reason:
            'طبق تاریخ ثبت‌شده، امتحان این درس $when است؛ '
            'یک مرور کوتاه و چند سؤال نمونه انجام بده.',
      ),
    );
  }

  // 2. Oldest overdue task.
  final overdue =
      tasks.where((task) {
        final due = parseDay(task['dueDate']);

        return task['done'] != true &&
            due != null &&
            _coachDayDifference(today, due) < 0;
      }).toList()..sort((a, b) {
        final dateOrder = _coachDayDifference(
          parseDay(b['dueDate'])!,
          parseDay(a['dueDate'])!,
        );

        if (dateOrder != 0) return dateOrder;

        final durationOrder = _safeCoachMinutes(
          a['minutes'],
          fallback: 30,
        ).compareTo(_safeCoachMinutes(b['minutes'], fallback: 30));

        if (durationOrder != 0) return durationOrder;

        return _cleanCoachText(
          a['title'],
        ).compareTo(_cleanCoachText(b['title']));
      });

  if (overdue.isNotEmpty) {
    final task = overdue.first;

    final title = _cleanCoachText(task['title'], fallback: 'کار عقب‌افتاده');

    final subject = _cleanCoachText(
      task['subject'],
      fallback: 'عمومی',
      maxLength: 100,
    );

    candidates.add(
      LearningCoachStep(
        title: 'شروع دوباره: $title',
        subject: subject,
        minutes: 15,
        kind: 'overdue',
        reason:
            'به‌جای جبران همه عقب‌ماندگی در یک روز، '
            'فقط ۱۵ دقیقه روی قدم اول این کار تمرکز کن. '
            'این قدم جایگزین خودکار کار اصلی نمی‌شود.',
      ),
    );
  }

  // 3. More practice, without labeling the learner's ability.
  final averages = subjectAverages(validExams);

  final practiceSubjects =
      averages.entries
          .where(
            (entry) =>
                entry.value.isFinite &&
                entry.value >= 0 &&
                entry.value < 60 &&
                (examCounts[entry.key] ?? 0) >= 2,
          )
          .toList()
        ..sort((a, b) {
          final averageOrder = a.value.compareTo(b.value);

          return averageOrder != 0 ? averageOrder : a.key.compareTo(b.key);
        });

  if (practiceSubjects.isNotEmpty) {
    final subject = practiceSubjects.first.key;

    candidates.add(
      LearningCoachStep(
        title: 'تمرین مفهومی $subject',
        subject: subject,
        minutes: 20,
        kind: 'practice',
        reason:
            'میانگین دو یا چند آزمون ثبت‌شده در این درس '
            'کمتر از ۶۰٪ است؛ '
            'یک مفهوم مشخص را مرور کن و سپس چند سؤال حل کن. '
            'این عدد ارزیابی توانایی یا استعداد تو نیست.',
      ),
    );
  }

  // 4. Active recall.
  final dueCards = cards.where((card) => isCardDue(card, now)).length;

  if (dueCards > 0) {
    candidates.add(
      LearningCoachStep(
        title: 'مرور فلش‌کارت‌های سررسیدشده',
        subject: 'مرور',
        minutes: 10,
        kind: 'retrieval',
        reason:
            '${toPersianDigits(dueCards)} فلش‌کارت '
            'برای مرور آماده است؛ '
            'در این نوبت کوتاه، هر تعداد که فرصت شد مرور کن '
            'و پاسخ را پیش از دیدن پشت کارت به یاد بیاور.',
      ),
    );
  }

  // 5. Gentle starter.
  if (candidates.isEmpty) {
    final hasOpenTasks = tasks.any((task) => task['done'] != true);

    candidates.add(
      LearningCoachStep(
        title: hasOpenTasks
            ? 'یک کار کوچک از برنامه‌ات'
            : 'یک نوبت یادآوری فعال',
        subject: 'عمومی',
        minutes: 15,
        kind: 'starter',
        reason: hasOpenTasks
            ? 'یکی از کارهای باز را انتخاب کن و فقط '
                  '۱۵ دقیقه روی آن کار کن. '
                  'لازم نیست همه کارها را یک‌باره تمام کنی.'
            : 'یک بخش کوتاه را بخوان، کتاب را ببند '
                  'و نکته‌های اصلی را از حافظه بنویس؛ '
                  'سپس پاسخ خودت را بررسی کن.',
      ),
    );
  }

  final unique = <String>{};
  final filtered = <LearningCoachStep>[];

  var remainingMinutes = available;
  var duplicateCount = 0;
  var budgetBlockedCount = 0;

  for (final step in candidates) {
    if (filtered.length >= 3) break;

    if (!unique.add(_coachStepKey(step))) continue;

    if (_coachAlreadyScheduled(tasks, step, today)) {
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

  if (filtered.isEmpty) {
    if (duplicateCount > 0) {
      notes.add(
        'بعضی قدم‌های پیشنهادی از قبل '
        'در برنامه امروزت ثبت شده‌اند؛ همان‌ها را ادامه بده.',
      );
    }

    if (budgetBlockedCount > 0) {
      notes.add(
        'ظرفیت آزاد امروز برای پیشنهادهای باقی‌مانده کافی نیست؛ '
        'می‌توانی آن‌ها را برای روز دیگری برنامه‌ریزی کنی.',
      );
    }
  }

  return LearningCoachPlan(
    steps: List<LearningCoachStep>.unmodifiable(filtered),
    availableMinutes: available,
    plannedMinutes: todayLoad,
    evidenceNotes: List<String>.unmodifiable(notes.toSet()),
  );
}

class _CoachSnapshot {
  const _CoachSnapshot({
    required this.dailyMinutes,
    required this.errors,
    this.plan,
  });

  final int dailyMinutes;
  final List<String> errors;
  final LearningCoachPlan? plan;

  bool get isUsable => errors.isEmpty && plan != null;
}

List<String> _coachReadErrors(EducationStore store) {
  return <String>{
    for (final key in _coachRelevantKeys)
      if (store.dataError(key) != null) store.dataError(key)!,
  }.toList(growable: false);
}

_CoachSnapshot _readCoachSnapshot(EducationStore store, DateTime now) {
  final existingErrors = _coachReadErrors(store);

  if (existingErrors.isNotEmpty) {
    return _CoachSnapshot(dailyMinutes: 120, errors: existingErrors);
  }

  try {
    final profile = store.profile;
    final exams = store.exams;
    final tasks = store.tasks;
    final cards = store.cards;
    final deadlines = store.deadlines;

    // Getters can discover errors while reading.
    final errors = _coachReadErrors(store);
    final dailyMinutes = _coachDailyMinutes(profile);

    if (errors.isNotEmpty) {
      return _CoachSnapshot(dailyMinutes: dailyMinutes, errors: errors);
    }

    return _CoachSnapshot(
      dailyMinutes: dailyMinutes,
      errors: const [],
      plan: buildLearningCoachPlan(
        exams: exams,
        tasks: tasks,
        cards: cards,
        deadlines: deadlines,
        now: now,
        dailyMinutes: dailyMinutes,
      ),
    );
  } on Object {
    final errors = _coachReadErrors(store);

    return _CoachSnapshot(
      dailyMinutes: 120,
      errors: errors.isNotEmpty
          ? errors
          : const [
              'ساخت پیشنهاد از اطلاعات فعلی انجام نشد. '
                  'داده‌ها را بررسی کن و دوباره تلاش کن.',
            ],
    );
  }
}

int _coachIdSequence = 0;

String _newCoachTaskId() {
  _coachIdSequence++;

  return 'coach-${DateTime.now().microsecondsSinceEpoch}'
      '-$_coachIdSequence';
}

class LearningCoachPage extends StatefulWidget {
  const LearningCoachPage({super.key, required this.store});

  final EducationStore store;

  @override
  State<LearningCoachPage> createState() => _LearningCoachPageState();
}

class _LearningCoachPageState extends State<LearningCoachPage> {
  // One in-flight save for the entire page, not one per step.
  String? _savingKey;

  Future<void> _addStep(
    LearningCoachStep displayedStep,
    String displayedDay,
  ) async {
    if (!mounted || _savingKey != null) return;

    final key = _coachStepKey(displayedStep);

    setState(() {
      _savingKey = key;
    });

    try {
      final now = DateTime.now();
      final todayKey = isoDay(startOfDay(now));

      if (todayKey != displayedDay) {
        showMessage(
          context,
          'روز تغییر کرده است؛ پیشنهادهای امروز را دوباره بررسی کن.',
        );
        return;
      }

      final snapshot = _readCoachSnapshot(widget.store, now);

      if (!snapshot.isUsable) {
        showMessage(context, 'اطلاعات فعلی قابل بررسی نیست؛ قدمی اضافه نشد.');
        return;
      }

      // Rebuild the plan rather than checking only the old time budget.
      // An exam, card or task may no longer justify the displayed action.
      LearningCoachStep? currentStep;

      for (final step in snapshot.plan!.steps) {
        if (_coachStepKey(step) == key &&
            step.minutes == displayedStep.minutes) {
          currentStep = step;
          break;
        }
      }

      if (currentStep == null) {
        showMessage(
          context,
          'پیشنهادها یا ظرفیت امروز تغییر کرده است؛ '
          'برنامه تازه را مرور کن.',
        );
        return;
      }

      await widget.store.addTask({
        'id': _newCoachTaskId(),
        'title': currentStep.title,
        'subject': currentStep.subject,
        'minutes': currentStep.minutes,
        'done': false,
        'dueDate': todayKey,
        'createdAt': now.toIso8601String(),
        'source': 'personal_learning_coach_v1',
      });

      if (mounted) {
        showMessage(context, 'این قدم به برنامه امروز اضافه شد.');
      }
    } on Object catch (error) {
      if (mounted) {
        showMessage(context, friendlyError(error));
      }
    } finally {
      if (mounted) {
        setState(() {
          _savingKey = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final now = DateTime.now();
        final displayedDay = isoDay(startOfDay(now));
        final snapshot = _readCoachSnapshot(widget.store, now);

        return Scaffold(
          appBar: AppBar(title: const Text('مربی یادگیری من')),
          body: SafeArea(
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (!snapshot.isUsable)
                    ..._buildErrorContent(context, snapshot)
                  else
                    ..._buildPlanContent(context, snapshot, displayedDay),
                  const SizedBox(height: 8),
                  const NoticeCard(
                    text:
                        'این ابزار مربی برنامه‌ریزی است، '
                        'نه آزمون استعداد یا تشخیص روان‌شناختی. '
                        'با داده کم، پیشنهادها مقدماتی‌اند. '
                        'ظرفیت نمایش‌داده‌شده از مدت کارهای باز '
                        'به دست می‌آید، نه اندازه‌گیری زمان واقعی مطالعه. '
                        'اگر امروز فرصت یا انرژی کافی نداری، '
                        'برنامه را سبک‌تر کن؛ '
                        'لازم نیست برای جبران، بیش از توانت درس بخوانی.',
                    icon: Icons.info_outline,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildErrorContent(
    BuildContext context,
    _CoachSnapshot snapshot,
  ) {
    return [
      const NoticeCard(
        text:
            'بخشی از اطلاعات قابل خواندن نیست '
            'یا ساخت پیشنهاد انجام نشده است. '
            'برای جلوگیری از برنامه‌ریزی بر اساس داده ناقص، '
            'پیشنهادها و افزودن قدم فعلاً غیرفعال‌اند.',
        icon: Icons.warning_amber_rounded,
        warning: true,
      ),
      for (final error in snapshot.errors)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(error, style: Theme.of(context).textTheme.bodySmall),
        ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _savingKey != null
            ? null
            : () {
                setState(() {});
              },
        icon: const Icon(Icons.refresh_outlined),
        label: const Text('بررسی دوباره اطلاعات'),
      ),
    ];
  }

  List<Widget> _buildPlanContent(
    BuildContext context,
    _CoachSnapshot snapshot,
    String displayedDay,
  ) {
    final plan = snapshot.plan!;
    final colors = Theme.of(context).colorScheme;

    final progress = (plan.plannedMinutes / snapshot.dailyMinutes)
        .clamp(0.0, 1.0)
        .toDouble();

    return [
      Card(
        color: colors.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: colors.onPrimaryContainer),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'قدم بعدی را آگاهانه انتخاب کنیم',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'این پیشنهادها فقط از نمره‌ها، برنامه‌ها، '
                  'امتحان‌ها و مرورهای ثبت‌شده '
                  'روی همین گوشی ساخته می‌شوند. '
                  'هیچ پیشنهادی بدون انتخاب تو '
                  'به برنامه اضافه نمی‌شود.',
                ),
                const SizedBox(height: 12),
                Text(
                  'مدت کارهای باز امروز: '
                  '${faNumber(plan.plannedMinutes)} دقیقه',
                ),
                Text(
                  'ظرفیت افزودن کار: '
                  '${faNumber(plan.availableMinutes)} دقیقه '
                  'از سقف تنظیم‌شده '
                  '${faNumber(snapshot.dailyMinutes)} دقیقه',
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: progress,
                  semanticsLabel: 'نسبت مدت کارهای باز امروز به سقف تنظیم‌شده',
                  semanticsValue: '${faNumber((progress * 100).round())} درصد',
                ),
              ],
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      for (final note in plan.evidenceNotes)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: NoticeCard(text: note, warning: true),
        ),
      if (plan.steps.isEmpty)
        EmptyState(
          title: plan.availableMinutes == 0
              ? 'ظرفیت افزودن کار امروز تکمیل شده است'
              : 'فعلاً قدم تازه‌ای پیشنهاد نمی‌شود',
          subtitle: plan.availableMinutes == 0
              ? 'کارهای باز امروز به سقف زمانی تنظیم‌شده رسیده‌اند. '
                    'این به معنی اندازه‌گیری زمان مطالعه نیست. '
                    'استراحت هم بخشی از یادگیری است.'
              : 'قدم‌ها ممکن است قبلاً ثبت شده باشند '
                    'یا در ظرفیت باقی‌مانده جا نشوند. '
                    'یادداشت‌های بالا را بررسی کن.',
          icon: Icons.check_circle_outline,
        ),
      for (final step in plan.steps)
        _buildStepCard(context, step, displayedDay),
    ];
  }

  Widget _buildStepCard(
    BuildContext context,
    LearningCoachStep step,
    String displayedDay,
  ) {
    final colors = Theme.of(context).colorScheme;
    final isSaving = _savingKey == _coachStepKey(step);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    step.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(step.reason, style: const TextStyle(height: 1.7)),
            const SizedBox(height: 8),
            Text(
              '${step.subject} · ${faNumber(step.minutes)} دقیقه',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.tonalIcon(
                onPressed: _savingKey != null
                    ? null
                    : () => _addStep(step, displayedDay),
                icon: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_task),
                label: Text(
                  isSaving ? 'در حال افزودن…' : 'افزودن به برنامه امروز',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
