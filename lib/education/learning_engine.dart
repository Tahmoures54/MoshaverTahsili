import 'dart:convert';

/// Pure learning logic: a bounded SM-2 variant, an adaptive study planner,
/// local analytics, daily suggestions and the backup file format.
///
/// No Flutter dependencies: every rule can be unit tested.
///
/// Outputs describe user-entered records, not ability, motivation, health
/// or guaranteed learning outcomes.
typedef Entry = Map<String, dynamic>;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

DateTime startOfDay(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

/// Date key in the form yyyy-MM-dd, used for task due dates.
String isoDay(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

/// Adds calendar days rather than elapsed 24-hour periods.
///
/// This avoids duplicate/skipped calendar dates across daylight-saving changes.
DateTime _addCalendarDays(DateTime value, int days) {
  return DateTime(value.year, value.month, value.day + days);
}

/// Difference between calendar dates, independent of daylight-saving changes.
int _calendarDaysBetween(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// Reads yyyy-MM-dd keys and ISO date-time records.
///
/// The written calendar date is preserved without timezone conversion.
/// Use this for calendar fields such as dueDate and deadline.date.
///
/// Invalid dates such as 2026-02-30 are rejected rather than normalized.
DateTime? parseDay(Object? value) {
  if (value == null) return null;

  final text = value.toString().trim();
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:$|[Tt ])').firstMatch(text);

  if (match == null) return null;

  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);

  if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }

  final date = DateTime(year, month, day);

  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }

  if (text.length > 10 && DateTime.tryParse(text) == null) {
    return null;
  }

  return date;
}

/// Reads a timestamp representing an instant.
///
/// Requires a date-time record rather than a date-only key.
/// Validates its calendar date before using Dart's ISO parser.
DateTime? _parseInstant(Object? value) {
  final text = value?.toString().trim() ?? '';

  if (text.length <= 10 || parseDay(text) == null) {
    return null;
  }

  return DateTime.tryParse(text);
}

String _digitsToEnglish(String value) {
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  const arabic = '٠١٢٣٤٥٦٧٨٩';
  const english = '0123456789';

  final buffer = StringBuffer();

  for (final rune in value.runes) {
    final char = String.fromCharCode(rune);
    final persianIndex = persian.indexOf(char);
    final arabicIndex = arabic.indexOf(char);

    if (persianIndex >= 0) {
      buffer.write(english[persianIndex]);
    } else if (arabicIndex >= 0) {
      buffer.write(english[arabicIndex]);
    } else {
      buffer.write(char);
    }
  }

  return buffer.toString();
}

num? _finiteNumberOf(Object? value) {
  if (value is num) {
    return value.isFinite ? value : null;
  }

  if (value is String) {
    final parsed = num.tryParse(_digitsToEnglish(value).trim());
    return parsed != null && parsed.isFinite ? parsed : null;
  }

  return null;
}

int _boundedInt(
  Object? value, {
  required int fallback,
  required int minimum,
  required int maximum,
}) {
  final number = _finiteNumberOf(value);

  if (number == null) {
    return fallback.clamp(minimum, maximum).toInt();
  }

  // Clamp before rounding, including for very large finite inputs.
  return number.clamp(minimum, maximum).round();
}

double _boundedDouble(
  Object? value, {
  required double fallback,
  required double minimum,
  required double maximum,
}) {
  final number = _finiteNumberOf(value);

  return (number ?? fallback).clamp(minimum, maximum).toDouble();
}

int _learningMinutes(Object? value, {int fallback = 0}) {
  return _boundedInt(value, fallback: fallback, minimum: 0, maximum: 1440);
}

/// Normalizes labels without truncating their identity.
///
/// Formatting-control characters are removed, whitespace is collapsed,
/// and common Arabic variants of Persian letters are normalized.
String _subjectOf(Object? value) {
  return (value?.toString() ?? '')
      .replaceAll(
        RegExp(
          r'[\u0000-\u001F\u007F-\u009F'
          r'\u061C\u200E\u200F\u202A-\u202E'
          r'\u2066-\u2069\uFEFF]',
        ),
        ' ',
      )
      .replaceAll('ي', 'ی')
      .replaceAll('ك', 'ک')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String toPersianDigits(Object value) {
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  const english = '0123456789';

  final buffer = StringBuffer();

  for (final rune in value.toString().runes) {
    final char = String.fromCharCode(rune);
    final index = english.indexOf(char);
    buffer.write(index < 0 ? char : persian[index]);
  }

  return buffer.toString();
}

/// Percentage of an exam, or null when incomplete or invalid.
///
/// Numeric strings are deliberately not accepted here: scored exams must
/// have numeric score/max fields, matching the application's stored schema.
double? examPercent(Entry exam) {
  final score = exam['score'];
  final max = exam['max'];

  if (score is! num || max is! num) return null;

  final s = score.toDouble();
  final m = max.toDouble();

  if (!s.isFinite || !m.isFinite || m <= 0 || s < 0 || s > m) {
    return null;
  }

  return s / m * 100;
}

/// Average percentage per normalized subject, using valid scored exams only.
Map<String, double> subjectAverages(List<Entry> exams) {
  final sums = <String, double>{};
  final counts = <String, int>{};

  for (final exam in exams) {
    final percent = examPercent(exam);
    final subject = _subjectOf(exam['subject']);

    if (percent == null || subject.isEmpty) continue;

    sums[subject] = (sums[subject] ?? 0.0) + percent;
    counts[subject] = (counts[subject] ?? 0) + 1;
  }

  return Map<String, double>.unmodifiable({
    for (final subject in sums.keys) subject: sums[subject]! / counts[subject]!,
  });
}

// ---------------------------------------------------------------------------
// Spaced repetition: bounded SM-2 variant
// ---------------------------------------------------------------------------

class ReviewState {
  const ReviewState({
    required this.ease,
    required this.interval,
    required this.reps,
    required this.lapses,
  });

  final double ease;
  final int interval;
  final int reps;
  final int lapses;
}

ReviewState reviewStateOf(Entry card) {
  return ReviewState(
    ease: _boundedDouble(
      card['ease'],
      fallback: 2.5,
      minimum: 1.3,
      maximum: 3.0,
    ),
    interval: _boundedInt(
      card['interval'],
      fallback: 0,
      minimum: 0,
      maximum: 365,
    ),
    reps: _boundedInt(card['reps'], fallback: 0, minimum: 0, maximum: 100000),
    lapses: _boundedInt(
      card['lapses'],
      fallback: 0,
      minimum: 0,
      maximum: 100000,
    ),
  );
}

ReviewState _normalizedReviewState(ReviewState state) {
  return reviewStateOf({
    'ease': state.ease,
    'interval': state.interval,
    'reps': state.reps,
    'lapses': state.lapses,
  });
}

/// Bounded SM-2 variant, preserving the application's previous behavior.
///
/// Quality:
/// 1 = forgot
/// 3 = recalled with difficulty
/// 4 = recalled
/// 5 = easy
///
/// Qualities below 3 restart at one day and retain the current ease.
/// Successful reviews use the updated ease for the next interval.
///
/// This is not an exact implementation of every classical SM-2 rule.
ReviewState sm2Next(ReviewState state, int quality) {
  if (quality < 0 || quality > 5) {
    throw RangeError.range(quality, 0, 5, 'quality');
  }

  final current = _normalizedReviewState(state);

  if (quality < 3) {
    return ReviewState(
      ease: current.ease,
      interval: 1,
      reps: 0,
      lapses: (current.lapses + 1).clamp(0, 100000).toInt(),
    );
  }

  final penalty = 5 - quality;
  final ease = (current.ease + (0.1 - penalty * (0.08 + penalty * 0.02)))
      .clamp(1.3, 3.0)
      .toDouble();

  final reps = (current.reps + 1).clamp(0, 100000).toInt();

  final interval = switch (reps) {
    1 => 1,
    2 => 6,
    _ => (current.interval * ease).round().clamp(1, 365).toInt(),
  };

  return ReviewState(
    ease: ease,
    interval: interval,
    reps: reps,
    lapses: current.lapses,
  );
}

List<Entry> _safeReviewHistory(Object? value) {
  if (value is! List) return <Entry>[];

  // Read backwards to retain at most the latest 99 usable records.
  final reversed = <Entry>[];

  for (var index = value.length - 1; index >= 0; index--) {
    final item = value[index];

    if (item is! Map || item.keys.any((key) => key is! String)) {
      continue;
    }

    reversed.add(Map<String, dynamic>.from(item));

    if (reversed.length == 99) break;
  }

  return reversed.reversed.toList();
}

Entry applyCardReview(Entry card, int quality, DateTime now) {
  final next = sm2Next(reviewStateOf(card), quality);
  final reviewedAt = now.toIso8601String();
  final history = _safeReviewHistory(card['reviewHistory']);

  history.add({
    'quality': quality,
    'reviewedAt': reviewedAt,
    'interval': next.interval,
    'ease': next.ease,
    'reps': next.reps,
    'lapses': next.lapses,
  });

  return {
    ...card,
    'ease': next.ease,
    'interval': next.interval,
    'reps': next.reps,
    'lapses': next.lapses,

    // Preserve existing elapsed-time scheduling for stored cards.
    'dueAt': now.add(Duration(days: next.interval)).toIso8601String(),
    'lastReviewedAt': reviewedAt,
    'reviewHistory': history,
  };
}

/// New cards without dueAt are immediately due.
///
/// A non-empty malformed dueAt is not silently interpreted as a new card;
/// reporting surfaces it as a data gap instead.
bool isCardDue(Entry card, DateTime now) {
  final raw = card['dueAt']?.toString().trim() ?? '';

  if (raw.isEmpty) return true;

  // Accept legacy date-only due values at local midnight.
  final due = raw.length == 10 ? parseDay(raw) : _parseInstant(raw);

  return due != null && !due.isAfter(now);
}

bool _hasInvalidCardDue(Entry card) {
  final raw = card['dueAt']?.toString().trim() ?? '';

  if (raw.isEmpty) return false;

  return raw.length == 10 ? parseDay(raw) == null : _parseInstant(raw) == null;
}

// ---------------------------------------------------------------------------
// Adaptive study planner
// ---------------------------------------------------------------------------

class PlanChange {
  const PlanChange({
    required this.taskId,
    required this.title,
    required this.newDate,
    required this.reason,
  });

  final String taskId;
  final String title;
  final String newDate;
  final String reason;
}

class AdaptivePlan {
  const AdaptivePlan({
    required this.assignments,
    required this.changes,
    required this.unplacedIds,
    required this.loadByDay,
  });

  /// Task id to yyyy-MM-dd for each unfinished task that could be placed.
  final Map<String, String> assignments;
  final List<PlanChange> changes;

  /// Identifiable tasks that do not fit within the planning horizon.
  final List<String> unplacedIds;
  final Map<String, int> loadByDay;
}

/// Builds a deterministic replacement plan for unfinished tasks.
///
/// Priority combines recorded subject averages and exam proximity.
/// Missing subject averages receive a neutral planning weight, not an
/// inferred score or an assessment of the learner.
///
/// Tasks are packed into the earliest non-rest days with sufficient room.
/// Existing future dates are not fixed reservations: they may move earlier.
///
/// Tasks without a usable id are ignored. Duplicate usable ids are rejected,
/// because assignments cannot represent two different tasks with one id.
AdaptivePlan buildAdaptivePlan({
  required List<Entry> tasks,
  required List<Entry> exams,
  required List<Entry> deadlines,
  required DateTime today,
  int dailyMinutes = 120,
  int horizonDays = 14,
  Set<int> restWeekdays = const {},
}) {
  final start = startOfDay(today);
  final cap = dailyMinutes.clamp(15, 240).toInt();
  final safeHorizonDays = horizonDays.clamp(1, 90).toInt();
  final mastery = subjectAverages(exams);

  final nearestDeadline = <String, int>{};

  for (final deadline in deadlines) {
    final date = parseDay(deadline['date']);
    final subject = _subjectOf(deadline['subject']);

    if (date == null || subject.isEmpty) continue;

    final days = _calendarDaysBetween(start, date);
    if (days < 0) continue;

    final previous = nearestDeadline[subject];

    if (previous == null || days < previous) {
      nearestDeadline[subject] = days;
    }
  }

  double priority(Entry task) {
    final subject = _subjectOf(task['subject']);
    final recordedAverage = mastery[subject];

    final practiceWeight = recordedAverage == null
        ? 50.0
        : 100.0 - recordedAverage;

    final days = nearestDeadline[subject];
    final urgency = days == null ? 0 : (30 - days).clamp(0, 30).toInt() * 2;

    return practiceWeight + urgency;
  }

  final seenIds = <String>{};
  final open = <Entry>[];

  for (final task in tasks) {
    if (task['done'] == true || task['id'] == null) continue;

    final id = task['id'].toString();

    if (id.trim().isEmpty) continue;

    if (!seenIds.add(id)) {
      throw ArgumentError('Duplicate task id in adaptive planner: $id');
    }

    open.add(task);
  }

  open.sort((a, b) {
    final byPriority = priority(b).compareTo(priority(a));
    if (byPriority != 0) return byPriority;

    return a['id'].toString().compareTo(b['id'].toString());
  });

  final days = List<DateTime>.generate(
    safeHorizonDays,
    (index) => _addCalendarDays(start, index),
    growable: false,
  );

  final loads = <int, int>{};

  int remaining(int index) {
    if (restWeekdays.contains(days[index].weekday)) return 0;
    return cap - (loads[index] ?? 0);
  }

  final assignments = <String, String>{};
  final changes = <PlanChange>[];
  final unplaced = <String>[];

  for (final task in open) {
    final id = task['id'].toString();
    final title = task['title']?.toString().trim() ?? '';

    final minutes = _boundedInt(
      task['minutes'],
      fallback: 30,
      minimum: 1,
      maximum: 1440,
    );

    int? chosen;

    for (var index = 0; index < safeHorizonDays; index++) {
      if (remaining(index) >= minutes) {
        chosen = index;
        break;
      }
    }

    if (chosen == null) {
      unplaced.add(id);
      continue;
    }

    loads[chosen] = (loads[chosen] ?? 0) + minutes;

    final chosenDay = days[chosen];
    final newDate = isoDay(chosenDay);
    assignments[id] = newDate;

    final currentDue = parseDay(task['dueDate']);

    if (currentDue != null && isoDay(currentDue) == newDate) {
      continue;
    }

    final String reason;

    if (currentDue != null && _calendarDaysBetween(start, currentDue) < 0) {
      reason =
          'این کار از موعد گذشته بود و با توجه به ترتیب اولویت‌ها، '
          'به اولین روز دارای ظرفیت منتقل شد.';
    } else if (currentDue != null &&
        _calendarDaysBetween(currentDue, chosenDay) > 0) {
      reason =
          'با ظرفیت و روزهای استراحت فعلی و ترتیب اولویت‌ها، '
          'این کار پس از موعد قبلی جا گرفت؛ موعد جدید را بررسی کن.';
    } else if (currentDue == null) {
      reason =
          'این کار موعد قابل خواندن نداشت و بر اساس اولویت‌های '
          'ثبت‌شده، در اولین روز دارای ظرفیت قرار گرفت.';
    } else {
      reason =
          'برای بازچینی کارهای باز در محدوده ظرفیت روزانه '
          'و حفظ روزهای استراحت جابه‌جا شد.';
    }

    changes.add(
      PlanChange(taskId: id, title: title, newDate: newDate, reason: reason),
    );
  }

  return AdaptivePlan(
    assignments: Map<String, String>.unmodifiable(assignments),
    changes: List<PlanChange>.unmodifiable(changes),
    unplacedIds: List<String>.unmodifiable(unplaced),
    loadByDay: Map<String, int>.unmodifiable({
      for (final entry in loads.entries) isoDay(days[entry.key]): entry.value,
    }),
  );
}

// ---------------------------------------------------------------------------
// Analytics
// ---------------------------------------------------------------------------

class SubjectProgress {
  const SubjectProgress({
    required this.subject,
    required this.average,
    required this.examCount,
    this.trend,
  });

  final String subject;
  final double average;
  final int examCount;

  /// Latest recorded exam minus the mean of earlier exams.
  ///
  /// Requires at least two valid exams and usable, distinct createdAt values
  /// for all exams in this subject. Otherwise chronology is uncertain.
  final double? trend;
}

class WeekLoad {
  const WeekLoad({
    required this.start,
    required this.plannedMinutes,
    required this.completedMinutes,
  });

  final DateTime start;

  /// Recorded task durations grouped by dueDate.
  final int plannedMinutes;

  /// Recorded durations of completed tasks grouped by completedAt.
  ///
  /// This is not measured study time.
  final int completedMinutes;
}

class LearningReport {
  const LearningReport({
    required this.subjects,
    required this.weeks,
    required this.adherence,
    required this.adherenceSample,
    required this.dueCards,
    required this.dataGaps,
  });

  final List<SubjectProgress> subjects;

  /// Four consecutive seven-day windows, oldest first, ending today.
  ///
  /// These are rolling windows, not necessarily named calendar weeks.
  final List<WeekLoad> weeks;

  /// Share of tasks with due dates in the previous 14 calendar days
  /// that are marked completed at report time.
  ///
  /// This does not measure on-time completion or actual study time.
  /// Field name retained for compatibility.
  final double? adherence;
  final int adherenceSample;
  final int dueCards;
  final List<String> dataGaps;

  /// Recorded averages at or above 75%; not an assessment of ability.
  List<SubjectProgress> get strengths {
    return subjects.where((s) => s.average >= 75).toList();
  }

  /// Recorded averages below 60%, lowest first.
  ///
  /// Consumers should check examCount before making subject-level advice.
  List<SubjectProgress> get weaknesses {
    return subjects.where((s) => s.average < 60).toList()..sort((a, b) {
      final byAverage = a.average.compareTo(b.average);
      return byAverage != 0 ? byAverage : a.subject.compareTo(b.subject);
    });
  }
}

LearningReport buildLearningReport({
  required List<Entry> exams,
  required List<Entry> tasks,
  required List<Entry> cards,
  required DateTime now,
}) {
  final today = startOfDay(now);

  final grouped = <String, List<({double percent, DateTime? date})>>{};

  var invalidScores = 0;
  var missingSubjects = 0;

  for (final exam in exams) {
    final percent = examPercent(exam);

    if (percent == null) {
      invalidScores++;
      continue;
    }

    final subject = _subjectOf(exam['subject']);

    if (subject.isEmpty) {
      missingSubjects++;
      continue;
    }

    grouped
        .putIfAbsent(subject, () => <({double percent, DateTime? date})>[])
        .add((percent: percent, date: _parseInstant(exam['createdAt'])));
  }

  final subjects = <SubjectProgress>[];
  var uncertainChronologySubjects = 0;

  for (final entry in grouped.entries) {
    final values = entry.value;
    final average =
        values.fold<double>(0.0, (sum, exam) => sum + exam.percent) /
        values.length;

    double? trend;

    if (values.length >= 2) {
      final uniqueTimes = <int>{};

      final hasCertainChronology = values.every((exam) {
        final date = exam.date;
        return date != null && uniqueTimes.add(date.microsecondsSinceEpoch);
      });

      if (hasCertainChronology) {
        final ordered = [...values]..sort((a, b) => a.date!.compareTo(b.date!));

        final earlierSum = ordered
            .take(ordered.length - 1)
            .fold<double>(0.0, (sum, exam) => sum + exam.percent);

        trend = ordered.last.percent - earlierSum / (ordered.length - 1);
      } else {
        uncertainChronologySubjects++;
      }
    }

    subjects.add(
      SubjectProgress(
        subject: entry.key,
        average: average,
        examCount: values.length,
        trend: trend,
      ),
    );
  }

  subjects.sort((a, b) {
    final byAverage = b.average.compareTo(a.average);
    return byAverage != 0 ? byAverage : a.subject.compareTo(b.subject);
  });

  final weeks = <WeekLoad>[];

  for (var back = 3; back >= 0; back--) {
    final weekStart = _addCalendarDays(today, -(back * 7 + 6));
    final weekEnd = _addCalendarDays(weekStart, 7);

    var planned = 0;
    var completed = 0;

    for (final task in tasks) {
      final minutes = _learningMinutes(task['minutes']);
      final due = parseDay(task['dueDate']);

      if (due != null && !due.isBefore(weekStart) && due.isBefore(weekEnd)) {
        planned += minutes;
      }

      final completedInstant = _parseInstant(task['completedAt']);
      final completedDay = completedInstant == null
          ? null
          : startOfDay(completedInstant.toLocal());

      if (task['done'] == true &&
          completedDay != null &&
          !completedDay.isBefore(weekStart) &&
          completedDay.isBefore(weekEnd)) {
        completed += minutes;
      }
    }

    weeks.add(
      WeekLoad(
        start: weekStart,
        plannedMinutes: planned,
        completedMinutes: completed,
      ),
    );
  }

  final windowStart = _addCalendarDays(today, -14);
  var sample = 0;
  var doneCount = 0;

  for (final task in tasks) {
    final due = parseDay(task['dueDate']);

    if (due == null || due.isBefore(windowStart) || !due.isBefore(today)) {
      continue;
    }

    sample++;

    if (task['done'] == true) {
      doneCount++;
    }
  }

  final usableScored = grouped.values.fold<int>(
    0,
    (sum, values) => sum + values.length,
  );

  final invalidTaskDates = tasks
      .where((task) => parseDay(task['dueDate']) == null)
      .length;

  final missingCompletionDates = tasks
      .where(
        (task) =>
            task['done'] == true && _parseInstant(task['completedAt']) == null,
      )
      .length;

  final invalidMinutes = tasks.where((task) {
    final number = _finiteNumberOf(task['minutes']);
    return number == null || number < 0 || number > 1440;
  }).length;

  final invalidCardDates = cards.where(_hasInvalidCardDue).length;
  final gaps = <String>[];

  if (usableScored == 0) {
    gaps.add('هنوز نمره معتبر همراه با نام درس ثبت نشده است.');
  } else if (usableScored < 3) {
    gaps.add(
      'تعداد نمره‌های قابل استفاده کم است؛ '
      'میانگین‌ها و روندهای نمایش‌داده‌شده مقدماتی‌اند.',
    );
  }

  if (subjects.any((subject) => subject.examCount < 2)) {
    gaps.add(
      'برای برخی درس‌ها فقط یک آزمون ثبت شده است؛ '
      'روند آن درس‌ها قابل محاسبه نیست.',
    );
  }

  if (uncertainChronologySubjects > 0) {
    gaps.add(
      'برای ${toPersianDigits(uncertainChronologySubjects)} درس، '
      'زمان ثبت آزمون‌ها ناقص یا یکسان است؛ '
      'روند زمانی آن‌ها نمایش داده نمی‌شود.',
    );
  }

  if (invalidScores > 0) {
    gaps.add(
      '${toPersianDigits(invalidScores)} نتیجه آزمون '
      'نمره معتبر ندارد و در میانگین‌ها استفاده نشده است.',
    );
  }

  if (missingSubjects > 0) {
    gaps.add(
      '${toPersianDigits(missingSubjects)} نتیجه آزمون '
      'نام درس ندارد و در تحلیل درس‌ها استفاده نشده است.',
    );
  }

  if (invalidTaskDates > 0) {
    gaps.add(
      '${toPersianDigits(invalidTaskDates)} کار '
      'موعد معتبر ندارد و در شاخص‌های مبتنی بر موعد '
      'محاسبه نشده است.',
    );
  }

  if (missingCompletionDates > 0) {
    gaps.add(
      '${toPersianDigits(missingCompletionDates)} کار تکمیل‌شده '
      'زمان تکمیل معتبر ندارد و در مجموع هفتگی '
      'کارهای تکمیل‌شده محاسبه نشده است.',
    );
  }

  if (invalidMinutes > 0) {
    gaps.add(
      'مدت ${toPersianDigits(invalidMinutes)} کار '
      'ناقص یا خارج از محدوده ۰ تا ۱۴۴۰ دقیقه است؛ '
      'برای محاسبه، مقدار ناخوانا صفر در نظر گرفته شده '
      'و مقدار خارج از محدوده محدود شده است.',
    );
  }

  if (invalidCardDates > 0) {
    gaps.add(
      '${toPersianDigits(invalidCardDates)} فلش‌کارت '
      'زمان مرور نامعتبر دارد و در شمارش کارت‌های '
      'سررسیدشده استفاده نشده است.',
    );
  }

  if (sample < 3) {
    gaps.add(
      'تعداد کارهای دارای موعد در بازه ۱۴ روزه کم است؛ '
      'شاخص تکمیل برنامه، در صورت نمایش، مقدماتی است.',
    );
  }

  return LearningReport(
    subjects: List<SubjectProgress>.unmodifiable(subjects),
    weeks: List<WeekLoad>.unmodifiable(weeks),
    adherence: sample == 0 ? null : doneCount / sample,
    adherenceSample: sample,
    dueCards: cards.where((card) => isCardDue(card, now)).length,
    dataGaps: List<String>.unmodifiable(gaps),
  );
}

// ---------------------------------------------------------------------------
// Daily suggestions
// ---------------------------------------------------------------------------

/// Up to three concrete suggestions.
///
/// Priority:
/// 1. Nearest exam within 0–3 calendar days.
/// 2. Today's overload warning.
/// 3. Overdue tasks.
/// 4. Practice based on at least two scored exams.
/// 5. Due flashcards.
///
/// These are suggestions, not reserved time slots. The coach/planner must
/// independently check capacity before adding tasks.
List<String> dailySuggestions({
  required LearningReport report,
  required List<Entry> tasks,
  required List<Entry> deadlines,
  required DateTime now,
  int dailyMinutes = 120,
}) {
  final today = startOfDay(now);
  final suggestions = <String>[];
  final dailyCap = dailyMinutes.clamp(15, 240).toInt();

  final upcoming =
      deadlines
          .map(
            (item) => (
              subject: _subjectOf(item['subject']),
              date: parseDay(item['date']),
            ),
          )
          .where((entry) {
            final date = entry.date;

            if (date == null || entry.subject.isEmpty) return false;

            final days = _calendarDaysBetween(today, date);
            return days >= 0 && days <= 3;
          })
          .toList()
        ..sort((a, b) {
          final dateOrder = a.date!.compareTo(b.date!);
          return dateOrder != 0 ? dateOrder : a.subject.compareTo(b.subject);
        });

  if (upcoming.isNotEmpty) {
    final exam = upcoming.first;
    final days = _calendarDaysBetween(today, exam.date!);

    final when = switch (days) {
      0 => 'امروز',
      1 => 'فردا',
      _ => 'تا ${toPersianDigits(days)} روز دیگر',
    };

    suggestions.add(
      'طبق تاریخ ثبت‌شده، امتحان ${exam.subject} $when است؛ '
      'مرور خلاصه و حل نمونه‌سؤال را اولویت بده.',
    );
  }

  final todayLoad = tasks.fold<int>(0, (sum, task) {
    final due = parseDay(task['dueDate']);

    if (task['done'] == true ||
        due == null ||
        _calendarDaysBetween(today, due) != 0) {
      return sum;
    }

    return sum + _learningMinutes(task['minutes']);
  });

  if (todayLoad > dailyCap) {
    suggestions.add(
      'مدت کارهای باز امروز ${toPersianDigits(todayLoad)} دقیقه است '
      'و از سقف ${toPersianDigits(dailyCap)} دقیقه‌ای تو بیشتر است. '
      'موعدها را بررسی کن و بخشی از کارهای قابل جابه‌جایی '
      'را به روز دیگری منتقل کن.',
    );
  }

  final overdue = tasks.where((task) {
    final due = parseDay(task['dueDate']);

    return task['done'] != true &&
        due != null &&
        _calendarDaysBetween(today, due) < 0;
  }).length;

  if (overdue > 0) {
    suggestions.add(
      '${toPersianDigits(overdue)} کار عقب‌افتاده داری؛ '
      'با توجه به موعدها، یک کار کوچک را انتخاب کن '
      'و فقط روی قدم اول آن تمرکز کن.',
    );
  }

  final practiceSubjects = report.weaknesses
      .where(
        (subject) =>
            subject.examCount >= 2 &&
            subject.average.isFinite &&
            subject.average >= 0,
      )
      .toList();

  if (practiceSubjects.isNotEmpty) {
    final subject = practiceSubjects.first;

    suggestions.add(
      'میانگین آزمون‌های ثبت‌شده ${subject.subject} '
      '${toPersianDigits(subject.average.round())}٪ است؛ '
      'اگر ظرفیت داری، یک نوبت ۲۰ دقیقه‌ای '
      'تمرین مفهومی و چند سؤال برنامه‌ریزی کن. '
      'این میانگین ارزیابی استعداد تو نیست.',
    );
  }

  if (report.dueCards > 0) {
    suggestions.add(
      '${toPersianDigits(report.dueCards)} فلش‌کارت '
      'برای مرور آماده است؛ اگر فرصت داری، '
      'یک نوبت ۱۰ دقیقه‌ای مرور کن. '
      'لازم نیست همه کارت‌ها را تمام کنی.',
    );
  }

  if (suggestions.isEmpty) {
    suggestions.add(
      'اگر فرصت و انرژی داری، یک کار کوچک را انتخاب کن '
      'و پس از انجام تیک بزن؛ استراحت هم بخشی از یادگیری است.',
    );
  }

  return List<String>.unmodifiable(suggestions.take(3));
}

// ---------------------------------------------------------------------------
// Backup format
// ---------------------------------------------------------------------------

class BackupFormatException implements Exception {
  const BackupFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Local workspace backup.
///
/// Wallet balances and purchase tokens are intentionally excluded.
///
/// IMPORTANT: backups can include private messages and teaching sessions.
/// Export/share UI must clearly disclose that to the user.
///
/// Structural validation is not a replacement for per-record validation
/// when the store reads or modifies data.
class WorkspaceBackup {
  const WorkspaceBackup._();

  static const format = 1;
  static const app = 'simorgh';
  static const maxBytes = 5 * 1024 * 1024;
  static const maxItemsPerKey = 5000;
  static const maxNestingDepth = 32;

  static const objectKeys = {'edu.profile', 'edu.career.draft'};

  static const listKeys = {
    'edu.tasks',
    'edu.exams',
    'edu.cards',
    'edu.messages',
    'edu.teaching.sessions',
    'edu.reports',
    'edu.deadlines',
  };

  static Set<String> get allowedKeys => {...objectKeys, ...listKeys};

  static String encode(Map<String, Object?> data, DateTime now) {
    // Validate before encoding, including cyclic or excessively deep values.
    _validateData(data);

    final String raw;

    try {
      raw = jsonEncode({
        'app': app,
        'format': format,
        'createdAt': now.toUtc().toIso8601String(),
        'data': data,
      });
    } on Object {
      throw const BackupFormatException(
        'بخشی از اطلاعات قابل تبدیل به پشتیبان نیست.',
      );
    }

    if (utf8.encode(raw).length > maxBytes) {
      throw const BackupFormatException(
        'حجم پشتیبان از حد مجاز بیشتر است؛ '
        'برای خروجی گرفتن، از روش پشتیبان‌گیری بخش‌بندی‌شده '
        'در صورت پشتیبانی برنامه استفاده کن.',
      );
    }

    // Export must never create a document this version cannot read.
    decode(raw);

    return raw;
  }

  static Map<String, Object?> decode(String raw) {
    // Cheap bound before allocating an additional UTF-8 byte buffer.
    if (raw.length > maxBytes) {
      throw const BackupFormatException('فایل پشتیبان بیش از حد بزرگ است.');
    }

    if (raw.trim().isEmpty) {
      throw const BackupFormatException('متنی برای بازیابی وارد نشده است.');
    }

    if (utf8.encode(raw).length > maxBytes) {
      throw const BackupFormatException('فایل پشتیبان بیش از حد بزرگ است.');
    }

    final Object? root;

    try {
      root = jsonDecode(raw);
    } on FormatException {
      throw const BackupFormatException('متن واردشده یک پشتیبان معتبر نیست.');
    }

    if (root is! Map ||
        root['app'] != app ||
        root['format'] != format ||
        root['data'] is! Map) {
      throw const BackupFormatException(
        'این پشتیبان مربوط به سیمرغ نیست '
        'یا نسخه آن پشتیبانی نمی‌شود.',
      );
    }

    final data = root['data'] as Map;
    _validateData(data);

    return {for (final entry in data.entries) entry.key as String: entry.value};
  }

  static void _validateData(Map<Object?, Object?> data) {
    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;

      if (key is! String || !allowedKeys.contains(key)) {
        throw BackupFormatException(
          'بخش ناشناخته «$key» در پشتیبان وجود دارد.',
        );
      }

      if (objectKeys.contains(key)) {
        if (value != null && value is! Map) {
          throw BackupFormatException('بخش «$key» در پشتیبان معتبر نیست.');
        }

        if (value is Map) {
          _checkItem(value);
          _checkJsonValue(value, 0);
        }

        continue;
      }

      if (value is! List) {
        throw BackupFormatException('بخش «$key» در پشتیبان معتبر نیست.');
      }

      if (value.length > maxItemsPerKey) {
        throw BackupFormatException('تعداد موارد «$key» بیش از حد مجاز است.');
      }

      final seenIds = <String>{};

      for (final item in value) {
        if (item is! Map) {
          throw BackupFormatException('بخش «$key» در پشتیبان معتبر نیست.');
        }

        _checkItem(item);
        _checkJsonValue(item, 0);

        final id = item['id'];

        // Legacy records may omit id. Existing ids must remain unique.
        if (id is String && !seenIds.add(id)) {
          throw BackupFormatException('بخش «$key» دارای شناسه تکراری است.');
        }

        _checkKnownFields(key, item);
      }
    }
  }

  static void _checkItem(Map<Object?, Object?> item) {
    final id = item['id'];

    if (id != null && (id is! String || id.trim().isEmpty || id.length > 160)) {
      throw const BackupFormatException(
        'یکی از موارد پشتیبان شناسه معتبر ندارد.',
      );
    }
  }

  /// Conservative field checks.
  ///
  /// Missing legacy fields remain allowed. Present fields must have compatible
  /// types, while incomplete scores/dates are surfaced by learning analytics.
  static void _checkKnownFields(String key, Map<Object?, Object?> item) {
    void checkText(String field) {
      final value = item[field];

      if (value != null && value is! String) {
        throw BackupFormatException(
          'فیلد «$field» در بخش «$key» باید متن باشد.',
        );
      }
    }

    void checkNumber(String field) {
      final value = item[field];

      if (value != null && _finiteNumberOf(value) == null) {
        throw BackupFormatException(
          'فیلد «$field» در بخش «$key» عدد معتبر ندارد.',
        );
      }
    }

    switch (key) {
      case 'edu.tasks':
        checkText('title');
        checkText('subject');
        checkText('dueDate');
        checkText('createdAt');
        checkText('completedAt');
        checkNumber('minutes');

        final done = item['done'];

        if (done != null && done is! bool) {
          throw const BackupFormatException(
            'وضعیت تکمیل یکی از کارها معتبر نیست.',
          );
        }

        final minutes = _finiteNumberOf(item['minutes']);

        if (minutes != null && (minutes < 0 || minutes > 1440)) {
          throw const BackupFormatException(
            'مدت یکی از کارها خارج از محدوده '
            '۰ تا ۱۴۴۰ دقیقه است.',
          );
        }

        break;

      case 'edu.exams':
        checkText('subject');
        checkText('createdAt');

        // examPercent intentionally requires numeric score/max values.
        for (final field in ['score', 'max']) {
          final value = item[field];

          if (value != null && (value is! num || !value.isFinite)) {
            throw BackupFormatException(
              'فیلد «$field» یکی از آزمون‌ها باید عدد معتبر باشد.',
            );
          }
        }

        break;

      case 'edu.cards':
        checkText('subject');
        checkText('dueAt');
        checkText('lastReviewedAt');
        checkText('createdAt');

        for (final field in ['ease', 'interval', 'reps', 'lapses']) {
          checkNumber(field);
        }

        final history = item['reviewHistory'];

        if (history != null) {
          if (history is! List ||
              history.length > maxItemsPerKey ||
              history.any((entry) => entry is! Map)) {
            throw const BackupFormatException(
              'سابقه مرور یکی از فلش‌کارت‌ها معتبر نیست.',
            );
          }
        }

        break;

      case 'edu.deadlines':
        checkText('subject');
        checkText('date');
        checkText('createdAt');
        break;

      default:
        // Other workspace sections retain flexible legacy schemas.
        break;
    }
  }

  /// Accepts only JSON-compatible values with bounded nesting.
  ///
  /// The depth bound also rejects cyclic structures before jsonEncode.
  static void _checkJsonValue(Object? value, int depth) {
    if (depth > maxNestingDepth) {
      throw const BackupFormatException(
        'ساختار یکی از بخش‌های پشتیبان بیش از حد تو‌در‌تو است.',
      );
    }

    if (value == null || value is String || value is bool) {
      return;
    }

    if (value is num) {
      if (!value.isFinite) {
        throw const BackupFormatException(
          'یکی از مقادیر عددی پشتیبان معتبر نیست.',
        );
      }

      return;
    }

    if (value is List) {
      for (final item in value) {
        _checkJsonValue(item, depth + 1);
      }

      return;
    }

    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw const BackupFormatException(
            'کلیدهای اطلاعات پشتیبان باید متنی باشند.',
          );
        }

        _checkJsonValue(entry.value, depth + 1);
      }

      return;
    }

    throw const BackupFormatException(
      'یکی از مقادیر پشتیبان از نوع قابل پشتیبانی نیست.',
    );
  }
}
