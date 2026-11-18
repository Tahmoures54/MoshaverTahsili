import 'dart:convert';

/// Pure learning logic: spaced repetition (SM-2), an adaptive study planner,
/// local analytics, daily suggestions and the backup file format.
///
/// This file deliberately does not import Flutter so every rule can be unit
/// tested. Every output is derived from data the student entered; nothing is
/// invented, and no result is presented as a guaranteed outcome.

typedef Entry = Map<String, dynamic>;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

DateTime startOfDay(DateTime value) => DateTime(value.year, value.month, value.day);

/// Date key in the form yyyy-MM-dd, used for task due dates.
String isoDay(DateTime value) {
  final day = startOfDay(value);
  return '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';
}

DateTime? parseDay(Object? value) {
  final parsed = DateTime.tryParse(value?.toString() ?? '');
  return parsed == null ? null : startOfDay(parsed);
}

int _intOf(Object? value, int fallback) =>
    value is num && value.isFinite ? value.round() : fallback;

double _doubleOf(Object? value, double fallback) =>
    value is num && value.isFinite ? value.toDouble() : fallback;

String toPersianDigits(Object value) {
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  final buffer = StringBuffer();
  for (final char in value.toString().split('')) {
    final index = '0123456789'.indexOf(char);
    buffer.write(index < 0 ? char : persian[index]);
  }
  return buffer.toString();
}

/// Percentage of an exam, or null when the record is incomplete or invalid.
double? examPercent(Entry exam) {
  final score = exam['score'];
  final max = exam['max'];
  if (score is! num || max is! num) return null;
  final s = score.toDouble();
  final m = max.toDouble();
  if (!s.isFinite || !m.isFinite || m <= 0 || s < 0 || s > m) return null;
  return s / m * 100;
}

DateTime _createdAt(Entry entry) =>
    DateTime.tryParse(entry['createdAt']?.toString() ?? '') ?? DateTime(2000);

/// Average percentage per subject, using only valid scored exams.
Map<String, double> subjectAverages(List<Entry> exams) {
  final sums = <String, double>{};
  final counts = <String, int>{};
  for (final exam in exams) {
    final percent = examPercent(exam);
    final subject = exam['subject']?.toString().trim() ?? '';
    if (percent == null || subject.isEmpty) continue;
    sums[subject] = (sums[subject] ?? 0.0) + percent;
    counts[subject] = (counts[subject] ?? 0) + 1;
  }
  return {for (final subject in sums.keys) subject: sums[subject]! / counts[subject]!};
}

// ---------------------------------------------------------------------------
// Spaced repetition (SM-2)
// ---------------------------------------------------------------------------

class ReviewState {
  const ReviewState({required this.ease, required this.interval, required this.reps, required this.lapses});
  final double ease;
  final int interval;
  final int reps;
  final int lapses;
}

ReviewState reviewStateOf(Entry card) => ReviewState(
      ease: _doubleOf(card['ease'], 2.5).clamp(1.3, 3.0).toDouble(),
      interval: _intOf(card['interval'], 0).clamp(0, 365),
      reps: _intOf(card['reps'], 0).clamp(0, 100000),
      lapses: _intOf(card['lapses'], 0).clamp(0, 100000),
    );

/// SM-2 scheduling. Quality: 1 = forgot, 3 = recalled with difficulty,
/// 4 = recalled, 5 = easy. Qualities below 3 restart the card at one day.
ReviewState sm2Next(ReviewState state, int quality) {
  if (quality < 0 || quality > 5) throw RangeError.range(quality, 0, 5, 'quality');
  if (quality < 3) {
    return ReviewState(ease: state.ease, interval: 1, reps: 0, lapses: state.lapses + 1);
  }
  final penalty = 5 - quality;
  final ease = (state.ease + (0.1 - penalty * (0.08 + penalty * 0.02))).clamp(1.3, 3.0).toDouble();
  final reps = state.reps + 1;
  final interval = switch (reps) {
    1 => 1,
    2 => 6,
    _ => (state.interval * ease).round().clamp(1, 365),
  };
  return ReviewState(ease: ease, interval: interval, reps: reps, lapses: state.lapses);
}

Entry applyCardReview(Entry card, int quality, DateTime now) {
  final next = sm2Next(reviewStateOf(card), quality);
  return {
    ...card,
    'ease': next.ease,
    'interval': next.interval,
    'reps': next.reps,
    'lapses': next.lapses,
    'dueAt': now.add(Duration(days: next.interval)).toIso8601String(),
    'lastReviewedAt': now.toIso8601String(),
  };
}

bool isCardDue(Entry card, DateTime now) {
  final due = DateTime.tryParse(card['dueAt']?.toString() ?? '');
  return due == null || !due.isAfter(now);
}

// ---------------------------------------------------------------------------
// Adaptive study planner
// ---------------------------------------------------------------------------

class PlanChange {
  const PlanChange({required this.taskId, required this.title, required this.newDate, required this.reason});
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
  /// Task id to yyyy-MM-dd for every undone task that could be placed.
  final Map<String, String> assignments;
  final List<PlanChange> changes;
  /// Tasks that do not fit in the horizon (for example, longer than one day's limit).
  final List<String> unplacedIds;
  final Map<String, int> loadByDay;
}

/// Builds a deterministic plan for undone tasks.
///
/// Priority: weaker subjects (lower average) and subjects with a near exam come
/// first. Each day has a study cap and optional rest weekdays (DateTime.weekday,
/// 1 = Monday ... 7 = Sunday). Overdue tasks move to the earliest day with room.
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
  final cap = dailyMinutes.clamp(15, 240);
  final mastery = subjectAverages(exams);

  final nearestDeadline = <String, int>{};
  for (final deadline in deadlines) {
    final date = parseDay(deadline['date']);
    final subject = deadline['subject']?.toString().trim() ?? '';
    if (date == null || subject.isEmpty) continue;
    final days = date.difference(start).inDays;
    if (days < 0) continue;
    final previous = nearestDeadline[subject];
    if (previous == null || days < previous) nearestDeadline[subject] = days;
  }

  double priority(Entry task) {
    final subject = task['subject']?.toString().trim() ?? '';
    final average = mastery[subject] ?? 50.0;
    final weakness = 100.0 - average;
    final days = nearestDeadline[subject];
    final urgency = days == null ? 0 : (30 - days).clamp(0, 30) * 2;
    return weakness + urgency;
  }

  final open = tasks.where((task) => task['done'] != true && task['id'] != null).toList()
    ..sort((a, b) {
      final byPriority = priority(b).compareTo(priority(a));
      if (byPriority != 0) return byPriority;
      return a['id'].toString().compareTo(b['id'].toString());
    });

  final loads = <int, int>{};
  bool isRest(int index) => restWeekdays.contains(start.add(Duration(days: index)).weekday);
  int remaining(int index) => isRest(index) ? 0 : cap - (loads[index] ?? 0);

  final assignments = <String, String>{};
  final changes = <PlanChange>[];
  final unplaced = <String>[];

  for (final task in open) {
    final id = task['id'].toString();
    final title = task['title']?.toString() ?? '';
    final minutes = _intOf(task['minutes'], 30).clamp(1, 1440);

    int? chosen;
    for (var index = 0; index < horizonDays; index++) {
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
    final newDate = isoDay(start.add(Duration(days: chosen)));
    assignments[id] = newDate;

    final currentDue = parseDay(task['dueDate']);
    final currentKey = task['dueDate']?.toString();
    if (currentKey == newDate) continue;

    final String reason;
    if (currentDue != null && currentDue.isBefore(start)) {
      reason = 'این کار از موعد گذشته بود و به اولین روز دارای ظرفیت منتقل شد.';
    } else if (currentDue != null && start.add(Duration(days: chosen)).isAfter(currentDue)) {
      reason = 'ظرفیت روزهای قبل از موعد پر است؛ کار به اولین فرصت ممکن منتقل شد.';
    } else if (currentDue == null) {
      reason = 'بر اساس اولویت درس و نزدیکی امتحان، برای این روز تنظیم شد.';
    } else {
      reason = 'برای متعادل‌کردن بار روزانه و حفظ روز استراحت جابه‌جا شد.';
    }
    changes.add(PlanChange(taskId: id, title: title, newDate: newDate, reason: reason));
  }

  return AdaptivePlan(
    assignments: assignments,
    changes: changes,
    unplacedIds: unplaced,
    loadByDay: {
      for (final entry in loads.entries) isoDay(start.add(Duration(days: entry.key))): entry.value,
    },
  );
}

// ---------------------------------------------------------------------------
// Analytics
// ---------------------------------------------------------------------------

class SubjectProgress {
  const SubjectProgress({required this.subject, required this.average, required this.examCount, this.trend});
  final String subject;
  final double average;
  final int examCount;
  /// Latest exam minus the mean of earlier exams; null with fewer than two exams.
  final double? trend;
}

class WeekLoad {
  const WeekLoad({required this.start, required this.plannedMinutes, required this.completedMinutes});
  final DateTime start;
  final int plannedMinutes;
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
  /// The last four weeks, oldest first.
  final List<WeekLoad> weeks;
  /// Share of past-due tasks (last 14 days) that were completed; null when none exist.
  final double? adherence;
  final int adherenceSample;
  final int dueCards;
  final List<String> dataGaps;

  List<SubjectProgress> get strengths => subjects.where((s) => s.average >= 75).toList();
  List<SubjectProgress> get weaknesses => subjects.where((s) => s.average < 60).toList();
}

LearningReport buildLearningReport({
  required List<Entry> exams,
  required List<Entry> tasks,
  required List<Entry> cards,
  required DateTime now,
}) {
  final today = startOfDay(now);

  final ordered = [...exams]..sort((a, b) => _createdAt(a).compareTo(_createdAt(b)));
  final percents = <String, List<double>>{};
  for (final exam in ordered) {
    final percent = examPercent(exam);
    final subject = exam['subject']?.toString().trim() ?? '';
    if (percent == null || subject.isEmpty) continue;
    percents.putIfAbsent(subject, () => <double>[]).add(percent);
  }

  final subjects = <SubjectProgress>[];
  for (final entry in percents.entries) {
    final values = entry.value;
    final average = values.reduce((a, b) => a + b) / values.length;
    double? trend;
    if (values.length >= 2) {
      final earlier = values.sublist(0, values.length - 1);
      trend = values.last - earlier.reduce((a, b) => a + b) / earlier.length;
    }
    subjects.add(SubjectProgress(
      subject: entry.key,
      average: average,
      examCount: values.length,
      trend: trend,
    ));
  }
  subjects.sort((a, b) => b.average.compareTo(a.average));

  final weeks = <WeekLoad>[];
  for (var back = 3; back >= 0; back--) {
    final weekStart = today.subtract(Duration(days: back * 7 + 6));
    final weekEnd = weekStart.add(const Duration(days: 7));
    var planned = 0;
    var completed = 0;
    for (final task in tasks) {
      final minutes = _intOf(task['minutes'], 0);
      final due = parseDay(task['dueDate']);
      if (due != null && !due.isBefore(weekStart) && due.isBefore(weekEnd)) planned += minutes;
      final doneAt = DateTime.tryParse(task['completedAt']?.toString() ?? '');
      if (task['done'] == true && doneAt != null && !doneAt.isBefore(weekStart) && doneAt.isBefore(weekEnd)) {
        completed += minutes;
      }
    }
    weeks.add(WeekLoad(start: weekStart, plannedMinutes: planned, completedMinutes: completed));
  }

  final windowStart = today.subtract(const Duration(days: 14));
  var sample = 0;
  var doneCount = 0;
  for (final task in tasks) {
    final due = parseDay(task['dueDate']);
    if (due == null || due.isBefore(windowStart) || !due.isBefore(today)) continue;
    sample++;
    if (task['done'] == true) doneCount++;
  }

  final scored = exams.where((exam) => examPercent(exam) != null).length;
  final gaps = <String>[];
  if (scored == 0) {
    gaps.add('هنوز نمره معتبری ثبت نشده است.');
  } else if (scored < 3) {
    gaps.add('برای تحلیل روند پیشرفت حداقل سه نمره معتبر لازم است.');
  }
  if (sample < 3) {
    gaps.add('برای سنجش پایبندی به برنامه، کارهای با تاریخ مشخص لازم است.');
  }

  return LearningReport(
    subjects: subjects,
    weeks: weeks,
    adherence: sample == 0 ? null : doneCount / sample,
    adherenceSample: sample,
    dueCards: cards.where((card) => isCardDue(card, now)).length,
    dataGaps: gaps,
  );
}

/// Up to three concrete suggestions for today. Wording never promises results.
List<String> dailySuggestions({
  required LearningReport report,
  required List<Entry> tasks,
  required List<Entry> deadlines,
  required DateTime now,
  int dailyMinutes = 120,
}) {
  final today = startOfDay(now);
  final todayKey = isoDay(today);
  final suggestions = <String>[];

  final overdue = tasks.where((task) {
    final due = parseDay(task['dueDate']);
    return task['done'] != true && due != null && due.isBefore(today);
  }).length;
  if (overdue > 0) {
    suggestions.add(
      '${toPersianDigits(overdue)} کار عقب‌افتاده داری؛ ابتدا کوتاه‌ترین آن‌ها را انجام بده تا بار برنامه سبک شود.',
    );
  }

  final todays = tasks.where((task) => task['done'] != true && task['dueDate']?.toString() == todayKey);
  final load = todays.fold<int>(0, (sum, task) => sum + _intOf(task['minutes'], 0));
  if (load > dailyMinutes) {
    suggestions.add(
      'بار امروز ${toPersianDigits(load)} دقیقه است و از سقف ${toPersianDigits(dailyMinutes)} دقیقه‌ای تو بیشتر است. '
      'بعضی کارها را به فردا منتقل کن.',
    );
  }

  for (final deadline in deadlines) {
    final date = parseDay(deadline['date']);
    if (date == null) continue;
    final days = date.difference(today).inDays;
    if (days < 0 || days > 3) continue;
    final when = days == 0 ? 'امروز' : 'تا ${toPersianDigits(days)} روز دیگر';
    suggestions.add(
      'امتحان ${deadline['subject']} $when است؛ مرور خلاصه و حل نمونه‌سؤال را اولویت بده.',
    );
    break;
  }

  if (report.weaknesses.isNotEmpty) {
    final weak = report.weaknesses.first;
    suggestions.add(
      'برای ${weak.subject} (میانگین ${toPersianDigits(weak.average.round())}٪) ۲۰ دقیقه تمرین مفهومی برنامه کن '
      'و سپس چند سؤال حل کن.',
    );
  }

  if (report.dueCards > 0) {
    suggestions.add(
      '${toPersianDigits(report.dueCards)} فلش‌کارت برای مرور امروز آماده است؛ ۱۰ دقیقه مرور کافی است.',
    );
  }

  if (suggestions.isEmpty) {
    suggestions.add('یک کار کوچک را انتخاب کن و پس از انجام تیک بزن؛ پیشرفت کوچک هم ثبت می‌شود.');
  }
  return suggestions.take(3).toList();
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

/// Local workspace backup. The AI wallet and purchase tokens are intentionally
/// excluded: credits must not be created by importing a file.
class WorkspaceBackup {
  const WorkspaceBackup._();

  static const format = 1;
  static const app = 'simorgh';
  static const maxBytes = 5 * 1024 * 1024;
  static const maxItemsPerKey = 5000;
  static const objectKeys = {'edu.profile', 'edu.career.draft'};
  static const listKeys = {
    'edu.tasks', 'edu.exams', 'edu.cards', 'edu.messages', 'edu.reports', 'edu.deadlines',
  };

  static Set<String> get allowedKeys => {...objectKeys, ...listKeys};

  static String encode(Map<String, Object?> data, DateTime now) => jsonEncode({
        'app': app,
        'format': format,
        'createdAt': now.toUtc().toIso8601String(),
        'data': data,
      });

  static Map<String, Object?> decode(String raw) {
    if (raw.trim().isEmpty) throw const BackupFormatException('متنی برای بازیابی وارد نشده است.');
    if (utf8.encode(raw).length > maxBytes) {
      throw const BackupFormatException('فایل پشتیبان بیش از حد بزرگ است.');
    }
    Object? root;
    try {
      root = jsonDecode(raw);
    } on FormatException {
      throw const BackupFormatException('متن وارد‌شده یک پشتیبان معتبر نیست.');
    }
    if (root is! Map || root['app'] != app || root['format'] != format || root['data'] is! Map) {
      throw const BackupFormatException('این پشتیبان مربوط به سیمرغ نیست یا نسخه آن پشتیبانی نمی‌شود.');
    }

    final data = root['data'] as Map;
    final result = <String, Object?>{};
    for (final entry in data.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || !allowedKeys.contains(key)) {
        throw BackupFormatException('بخش ناشناخته «$key» در پشتیبان وجود دارد.');
      }
      if (objectKeys.contains(key)) {
        if (value != null && value is! Map) {
          throw BackupFormatException('بخش «$key» در پشتیبان معتبر نیست.');
        }
        if (value is Map) _checkItem(value);
      } else {
        if (value is! List) throw BackupFormatException('بخش «$key» در پشتیبان معتبر نیست.');
        if (value.length > maxItemsPerKey) {
          throw BackupFormatException('تعداد موارد «$key» بیش از حد مجاز است.');
        }
        for (final item in value) {
          if (item is! Map) throw BackupFormatException('بخش «$key» در پشتیبان معتبر نیست.');
          _checkItem(item);
        }
      }
      result[key] = value;
    }
    return result;
  }

  static void _checkItem(Map<Object?, Object?> item) {
    final id = item['id'];
    if (id != null && (id is! String || id.length > 160)) {
      throw const BackupFormatException('یکی از موارد پشتیبان معتبر نیست.');
    }
  }
}
