import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ui.dart';

enum SimorghMood { welcome, thinking, encouraging, celebrating, gentle }

enum SimorghAction { planner, review, advisor }

enum SimorghChatState { listening, empathetic, thinking, happy, guiding }

extension SimorghChatStatePresentation on SimorghChatState {
  String get label => switch (this) {
    SimorghChatState.listening => 'شنونده · با دقت همراهت هستم',
    SimorghChatState.empathetic => 'همدل · با هم مسئله را روشن کنیم',
    SimorghChatState.thinking => 'متفکر · دارم پاسخ را آماده می‌کنم',
    SimorghChatState.happy => 'خوشحال · پیشرفتت ارزشمند است',
    SimorghChatState.guiding => 'راهنما · قدم بعدی را پیدا کنیم',
  };

  SimorghMood get visualMood => switch (this) {
    SimorghChatState.listening => SimorghMood.welcome,
    SimorghChatState.empathetic => SimorghMood.gentle,
    SimorghChatState.thinking => SimorghMood.thinking,
    SimorghChatState.happy => SimorghMood.celebrating,
    SimorghChatState.guiding => SimorghMood.encouraging,
  };
}

// Compiled once, rather than on every call.
final RegExp _whitespace = RegExp(r'\s+');

final RegExp _directionalControls = RegExp(
  r'[\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069\uFEFF]',
);

final RegExp _calendarPrefix = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:$|[Tt ])');

final RegExp _empatheticLanguage = RegExp(
  r'نگران|می\s*ترسم|خسته|استرس|ناامید|نا\s+امید|'
  r'غمگین|سخته|سخت\s+است|'
  r'نمی\s*توانم|نمی\s*تونم|'
  r'از\s+عهده\s*(?:اش|ش)?\s*برنمی\s*(?:آیم|ایم|آییم|اییم)|'
  r'کم\s+آوردم',
);

final RegExp _encouragingLanguage = RegExp(
  r'آفرین|تبریک|'
  r'پیشرفت\s+(?:کردی|داشتی|خوبی|ارزشمند)|'
  r'تمام\s+کردی|موفق\s+شدی|به\s+پایان\s+رساندی',
);

/// Normalizes text only for comparisons.
///
/// The original stored text is never changed.
/// Non-string values are not converted into conversation text.
String _normalizePersianText(Object? value) {
  if (value is! String) return '';

  return value
      .replaceAll('ي', 'ی')
      .replaceAll('ك', 'ک')
      .replaceAll('\u200C', ' ')
      .replaceAll(_directionalControls, '')
      .replaceAll(_whitespace, ' ')
      .trim();
}

String _normalizeDateDigits(String value) {
  const persian = '۰۱۲۳۴۵۶۷۸۹';
  const arabic = '٠١٢٣٤٥٦٧٨٩';

  var result = value.trim();

  for (var i = 0; i < 10; i++) {
    result = result.replaceAll(persian[i], '$i').replaceAll(arabic[i], '$i');
  }

  return result;
}

/// Selects a presentation state from visible text and request status.
///
/// This is a keyword-based UI heuristic. It does not detect emotions,
/// diagnose mental health, or assess the truth of a message.
SimorghChatState resolveSimorghChatState({
  required bool busy,
  required List<Map<String, dynamic>> messages,
}) {
  if (busy) return SimorghChatState.thinking;

  // Ignore system/tool messages and empty or malformed content.
  for (var i = messages.length - 1; i >= 0; i--) {
    final message = messages[i];
    final role = _normalizePersianText(message['role']).toLowerCase();

    if (role != 'assistant' && role != 'user') continue;

    final content = _normalizePersianText(message['content']);
    if (content.isEmpty) continue;

    if (role == 'assistant') {
      return _encouragingLanguage.hasMatch(content)
          ? SimorghChatState.happy
          : SimorghChatState.guiding;
    }

    return _empatheticLanguage.hasMatch(content)
        ? SimorghChatState.empathetic
        : SimorghChatState.listening;
  }

  return SimorghChatState.listening;
}

@immutable
class SimorghGuidance {
  const SimorghGuidance({
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.action,
    required this.mood,
  });

  final String title;
  final String message;
  final String actionLabel;
  final SimorghAction action;
  final SimorghMood mood;
}

/// Reads a valid Gregorian calendar prefix.
///
/// Supports YYYY-MM-DD and ISO-like timestamps.
/// Date rollover such as February 30 is explicitly rejected.
DateTime? _calendarDayFromText(String text) {
  final match = _calendarPrefix.firstMatch(text);
  if (match == null) return null;

  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);

  if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }

  final result = DateTime.utc(year, month, day);

  if (result.year != year || result.month != month || result.day != day) {
    return null;
  }

  return result;
}

/// Parses day-based task deadlines without shifting the written date
/// because of a timezone offset.
///
/// For timestamp strings, the entire timestamp must also be valid.
DateTime? _parseTaskDay(Object? value) {
  if (value is DateTime) {
    return DateTime.utc(value.year, value.month, value.day);
  }

  if (value is! String) return null;

  final text = _normalizeDateDigits(value);
  if (text.isEmpty || text.length > 100) return null;

  final day = _calendarDayFromText(text);
  if (day == null) return null;

  if (text.length != 10 && _parseInstant(text) == null) {
    return null;
  }

  return day;
}

/// Parses an instant while rejecting normalized invalid date/time fields.
///
/// Offset-free timestamps follow Dart's local-time interpretation.
/// Date-only ISO values are supported for existing stored data.
DateTime? _parseInstant(Object? value) {
  if (value is DateTime) return value;
  if (value is! String) return null;

  final text = _normalizeDateDigits(value);
  if (text.isEmpty || text.length > 100) return null;

  if (_calendarDayFromText(text) == null) return null;

  final parsed = DateTime.tryParse(text);
  if (parsed == null) return null;

  // Validate time components before Dart can normalize them.
  if (text.length > 10) {
    final timeMatch = _isoTime.firstMatch(text.substring(10));
    if (timeMatch == null) return null;

    final hour = int.parse(timeMatch.group(1)!);
    final minute = int.parse(timeMatch.group(2)!);
    final second = int.parse(timeMatch.group(3) ?? '0');

    if (hour > 23 || minute > 59 || second > 59) {
      return null;
    }

    final offsetHour = timeMatch.group(4);
    final offsetMinute = timeMatch.group(5);

    if (offsetHour != null &&
        (int.parse(offsetHour) > 23 || int.parse(offsetMinute ?? '0') > 59)) {
      return null;
    }
  }

  return parsed;
}

final RegExp _isoTime = RegExp(
  r'^[Tt ](\d{2}):?(\d{2})'
  r'(?::?(\d{2})(?:[.,]\d+)?)?'
  r'(?:[Zz]|[+-](\d{2})(?::?(\d{2}))?)?$',
);

bool _isSameLocalDay(DateTime value, DateTime reference) {
  final localValue = value.toLocal();
  final localReference = reference.toLocal();

  return localValue.year == localReference.year &&
      localValue.month == localReference.month &&
      localValue.day == localReference.day;
}

bool _isMissingDueDate(Object? value) {
  return value == null || (value is String && value.trim().isEmpty);
}

/// Selects supportive guidance using only the supplied task/card records.
///
/// Priority:
/// overdue tasks -> due cards -> today's completion -> first setup
/// -> pending tasks -> maintenance.
///
/// Missing card dueAt values retain the store's new/due-card convention.
/// Malformed non-empty dates are ignored rather than counted as due.
///
/// Duplicate input records are counted separately because this function
/// does not assume a particular identifier schema.
///
/// Supply now explicitly for deterministic tests.
SimorghGuidance buildSimorghGuidance({
  required List<Map<String, dynamic>> tasks,
  required List<Map<String, dynamic>> cards,
  DateTime? now,
  String grade = '',
}) {
  final reference = now ?? DateTime.now();
  final localToday = reference.toLocal();

  // UTC is used here only as a stable calendar-date comparison key.
  final day = DateTime.utc(localToday.year, localToday.month, localToday.day);

  var overdueTasks = 0;
  var completedToday = 0;
  var pendingTasks = 0;
  var dueCards = 0;

  for (final task in tasks) {
    if (task['done'] == true) {
      final completedAt = _parseInstant(task['completedAt']);

      if (completedAt != null &&
          !completedAt.isAfter(reference) &&
          _isSameLocalDay(completedAt, reference)) {
        completedToday++;
      }

      continue;
    }

    pendingTasks++;

    final due = _parseTaskDay(task['dueDate']);

    if (due != null && due.isBefore(day)) {
      overdueTasks++;
    }
  }

  for (final card in cards) {
    final rawDue = card['dueAt'];

    if (_isMissingDueDate(rawDue)) {
      dueCards++;
      continue;
    }

    final due = _parseInstant(rawDue);

    if (due != null && !due.isAfter(reference)) {
      dueCards++;
    }
  }

  final normalizedGrade = _normalizePersianText(grade);
  final isPrimary = normalizedGrade == 'ابتدایی';

  final isOlderStudent = const {
    'متوسطه دوم',
    'دانشآموز کنکوری',
    'دانش آموز کنکوری',
    'دانشجو',
  }.contains(normalizedGrade);

  if (overdueTasks > 0) {
    return SimorghGuidance(
      title: 'لازم نیست همه‌چیز را یک‌جا حل کنی',
      message: isPrimary
          ? '${faNumber(overdueTasks)} کار از زمان برنامه‌ات گذشته. '
                'بیا یکی را انتخاب کنیم و قدم‌به‌قدم پیش برویم.'
          : isOlderStudent
          ? '${faNumber(overdueTasks)} کار از برنامه عقب مانده است. '
                'یکی را اولویت‌بندی کن یا زمان‌بندی را '
                'واقع‌بینانه‌تر تنظیم کن.'
          : '${faNumber(overdueTasks)} کار از زمان برنامه‌ریزی‌شده '
                'گذشته. یکی را انتخاب کن و اگر لازم بود، '
                'برنامه را واقع‌بینانه‌تر بچین.',
      actionLabel: 'مرتب‌کردن برنامه',
      action: SimorghAction.planner,
      mood: SimorghMood.gentle,
    );
  }

  if (dueCards > 0) {
    return SimorghGuidance(
      title: 'وقت یک مرور کوتاه است',
      message: isPrimary
          ? '${faNumber(dueCards)} کارت برای مرور آماده است. '
                'بیا چندتایشان را یادآوری کنیم.'
          : '${faNumber(dueCards)} فلش‌کارت برای مرور آماده است. '
                'پیش از دیدن پاسخ، تلاش کن آن را از حافظه بازیابی کنی.',
      actionLabel: 'شروع مرور',
      action: SimorghAction.review,
      mood: SimorghMood.thinking,
    );
  }

  if (completedToday > 0) {
    return SimorghGuidance(
      title: 'یک قدم واقعی برداشتی!',
      message: isPrimary
          ? 'آفرین! امروز ${faNumber(completedToday)} کار را تمام کردی. '
                'هر قدم کوچک ارزشمند است؛ استراحت هم یادت نرود.'
          : 'امروز ${faNumber(completedToday)} کار را به پایان رساندی. '
                'این پیشرفت ارزشمند است؛ برای قدم بعدی یا '
                'یک استراحت کوتاه تصمیم بگیر.',
      actionLabel: 'دیدن برنامه',
      action: SimorghAction.planner,
      mood: SimorghMood.celebrating,
    );
  }

  if (tasks.isEmpty && cards.isEmpty) {
    return SimorghGuidance(
      title: isOlderStudent
          ? 'یک هدف روشن برای شروع انتخاب کن'
          : 'سفر یادگیری از یک قدم آغاز می‌شود',
      message: isPrimary
          ? 'هنوز برنامه‌ای ثبت نکرده‌ای. '
                'یک کار کوچک و دوست‌داشتنی برای شروع انتخاب کن.'
          : isOlderStudent
          ? 'هنوز برنامه یا فلش‌کارتی ثبت نکرده‌ای. '
                'یک هدف کوچک، مشخص و قابل‌اندازه‌گیری تعیین کن.'
          : 'هنوز برنامه یا فلش‌کارتی ثبت نکرده‌ای. '
                'یک هدف کوچک و شدنی انتخاب کن؛ '
                'لازم نیست همه‌چیز از اول کامل باشد.',
      actionLabel: 'ساخت اولین برنامه',
      action: SimorghAction.planner,
      mood: SimorghMood.welcome,
    );
  }

  if (pendingTasks > 0) {
    return SimorghGuidance(
      title: 'قدم بعدی را خودت انتخاب کن',
      message: isPrimary
          ? '${faNumber(pendingTasks)} کار در برنامه‌ات مانده. '
                'اگر زمان انجامش رسیده، از یک کار کوتاه شروع کن.'
          : isOlderStudent
          ? '${faNumber(pendingTasks)} کار باز داری؛ '
                'قدم بعدی را بر اساس موعد، اهمیت و زمان لازم انتخاب کن.'
          : '${faNumber(pendingTasks)} کار ناتمام در برنامه‌ات داری. '
                'موعدشان را بررسی کن و یک قدم کوتاه '
                'یا مهم برای ادامه انتخاب کن.',
      actionLabel: 'رفتن به برنامه',
      action: SimorghAction.planner,
      mood: SimorghMood.encouraging,
    );
  }

  return SimorghGuidance(
    title: 'برای ادامه عجله لازم نیست',
    message: cards.isNotEmpty
        ? 'فعلاً کارت آمادهٔ مرور و کار ناتمامی در برنامه دیده نمی‌شود. '
              'می‌توانی استراحت کنی یا برای هدف بعدی برنامه بریزی.'
        : 'برنامه فعلی‌ات کار ناتمامی ندارد. '
              'اگر زمان و انرژی داری، یک هدف تازه و واقع‌بینانه انتخاب کن؛ '
              'استراحت هم بخشی از مسیر است.',
    actionLabel: 'دیدن برنامه',
    action: SimorghAction.planner,
    mood: SimorghMood.encouraging,
  );
}

/// Compact static mascot for the chat header.
class SimorghChatAvatar extends StatelessWidget {
  const SimorghChatAvatar({super.key, required this.state});

  final SimorghChatState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Row(
        children: [
          const SizedBox(width: 2),
          ExcludeSemantics(
            child: RepaintBoundary(
              child: SizedBox(
                width: 62,
                height: 72,
                child: CustomPaint(
                  key: const ValueKey('simorgh-chat-avatar'),
                  painter: _SimorghCompanionPainter(
                    phase: 0.5,
                    mood: state.visualMood,
                    dark: theme.brightness == Brightness.dark,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'سیمرغ',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Semantics(
                  // Avoid repeatedly announcing state changes during chat.
                  liveRegion: false,
                  child: Text(
                    state.label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                      height: 1.6,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'همراه تو در مسیر دانایی',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SimorghCompanion extends StatefulWidget {
  const SimorghCompanion({
    super.key,
    required this.tasks,
    required this.cards,
    required this.onAction,
    required this.onChat,
    this.now,
    this.grade = '',
    this.active = true,
  });

  final List<Map<String, dynamic>> tasks;
  final List<Map<String, dynamic>> cards;
  final ValueChanged<SimorghAction> onAction;
  final VoidCallback onChat;
  final DateTime? now;
  final String grade;

  /// Set false when the containing tab/page is not visible.
  final bool active;

  @override
  State<SimorghCompanion> createState() => _SimorghCompanionState();
}

class _SimorghCompanionState extends State<SimorghCompanion>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _animation;

  bool _foreground = true;
  bool _motionEnabled = false;

  @override
  void initState() {
    super.initState();

    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;

    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );

    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant SimorghCompanion oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.active != widget.active) {
      _syncAnimation();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;

    if (!mounted) return;

    // Lifecycle notifications do not otherwise rebuild this widget.
    setState(_syncAnimation);
  }

  void _syncAnimation() {
    final media = MediaQuery.maybeOf(context);
    final reduceMotion = media?.disableAnimations ?? false;

    _motionEnabled =
        widget.active && _foreground && !reduceMotion && TickerMode.of(context);

    if (_motionEnabled) {
      if (!_animation.isAnimating) {
        _animation.repeat();
      }
    } else {
      _animation.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animation.dispose();
    super.dispose();
  }

  Widget _buildMascot(SimorghGuidance guidance, ThemeData theme) {
    return Semantics(
      image: true,
      label: 'سیمرغ، همراه مسیر یادگیری',
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: SizedBox(
            width: 100,
            height: 124,
            child: CustomPaint(
              key: const ValueKey('simorgh-character-painter'),
              painter: _SimorghCompanionPainter(
                phase: 0.5,
                mood: guidance.mood,
                animation: _motionEnabled ? _animation : null,
                dark: theme.brightness == Brightness.dark,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildText(SimorghGuidance guidance, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'همراه تو، سیمرغ',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 7),
        Semantics(
          header: true,
          child: Text(
            guidance.title,
            style: theme.textTheme.titleMedium?.copyWith(
              height: 1.6,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          guidance.message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.85,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;

    final guidance = buildSimorghGuidance(
      tasks: widget.tasks,
      cards: widget.cards,
      now: widget.now,
      grade: widget.grade,
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: dark
                  ? [
                      colors.surface,
                      Color.alphaBlend(
                        colors.primary.withValues(alpha: 0.10),
                        colors.surface,
                      ),
                    ]
                  : [
                      Color.alphaBlend(
                        colors.tertiary.withValues(alpha: 0.04),
                        colors.surface,
                      ),
                      Color.alphaBlend(
                        colors.primary.withValues(alpha: 0.07),
                        colors.surface,
                      ),
                    ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final largeText =
                    MediaQuery.textScalerOf(context).scale(14) > 19;
                final stacked = constraints.maxWidth < 330 || largeText;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (stacked) ...[
                      Center(child: _buildMascot(guidance, theme)),
                      const SizedBox(height: 10),
                      _buildText(guidance, theme),
                    ] else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _buildMascot(guidance, theme),
                          const SizedBox(width: 12),
                          Expanded(child: _buildText(guidance, theme)),
                        ],
                      ),
                    const SizedBox(height: 14),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: widget.onChat,
                          icon: const Icon(Icons.chat_bubble_outline, size: 18),
                          label: const Text('گفت‌وگو با سیمرغ'),
                        ),
                        FilledButton.tonal(
                          onPressed: () => widget.onAction(guidance.action),
                          child: Text(guidance.actionLabel),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Vector-only Persian Simorgh.
///
/// Design coordinates use a 100 x 124 canvas. Wings, crown and tail
/// fit inside that area, including the celebratory sparks.
///
/// Animation ticks repaint only the canvas, not the surrounding widgets.
class _SimorghCompanionPainter extends CustomPainter {
  _SimorghCompanionPainter({
    required this.phase,
    required this.mood,
    this.animation,
    this.dark = false,
  }) : super(repaint: animation);

  final double phase;
  final SimorghMood mood;
  final Animation<double>? animation;
  final bool dark;

  static const Color _navy = Color(0xFF142D4E);
  static const Color _blue = Color(0xFF236B9A);
  static const Color _teal = Color(0xFF20B8AE);
  static const Color _deepTeal = Color(0xFF087F83);
  static const Color _gold = Color(0xFFF2BE58);
  static const Color _cream = Color(0xFFFFF1D0);

  void _shape(Canvas canvas, Path path, Color color, {bool outlined = false}) {
    canvas.drawPath(path, Paint()..color = color);

    if (outlined) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7
          ..color = _cream.withValues(alpha: 0.65),
      );
    }
  }

  void _drawTail(Canvas canvas, double wave) {
    const colors = [_blue, _deepTeal, _gold, _teal, _blue];

    for (var i = 0; i < colors.length; i++) {
      final x = (i - 2) * 7.0;
      final sway = wave * (i.isEven ? 1.4 : -1.4);

      final feather = Path()
        ..moveTo(x * 0.2 - 4, 17)
        ..cubicTo(x - 8 + sway, 32, x + 10 + sway, 43, x + sway, 53)
        ..cubicTo(x - 7 + sway, 43, x - 8 + sway, 31, x * 0.2 + 1, 18)
        ..close();

      _shape(canvas, feather, colors[i]);

      canvas.drawLine(
        Offset(x * 0.2 - 1, 20),
        Offset(x + sway, 47),
        Paint()
          ..color = _cream.withValues(alpha: 0.5)
          ..strokeWidth = 0.7
          ..strokeCap = StrokeCap.round,
      );
    }

    canvas.drawCircle(const Offset(0, 46), 3.4, Paint()..color = _gold);
    canvas.drawCircle(const Offset(0, 46), 1.7, Paint()..color = _teal);
  }

  void _drawWing(Canvas canvas, {required bool near, required double lift}) {
    canvas.save();

    if (!near) {
      canvas.scale(-1, 1);
    }

    final wing = Path()
      ..moveTo(5, -7)
      ..cubicTo(20, -24 - lift, 35, -46 - lift, 47, -40 - lift * 0.6)
      ..cubicTo(49, -28, 40, -14, 29, -7)
      ..cubicTo(39, -10, 39, 1, 28, 8)
      ..cubicTo(34, 8, 31, 17, 19, 18)
      ..cubicTo(13, 8, 8, 1, 5, -7)
      ..close();

    _shape(canvas, wing, near ? _blue : _deepTeal);

    for (var i = 0; i < 7; i++) {
      final x = 39.0 - i * 4.3;

      final feather = Path()
        ..moveTo(12, -3 + i * 1.8)
        ..cubicTo(
          x + 4,
          -19 - lift,
          x + 5,
          -36 - lift * 0.55,
          x - 1,
          -40 - lift * 0.55,
        )
        ..cubicTo(x - 9, -26 - lift * 0.4, x - 6, -12, 7 - i * 0.8, 8)
        ..close();

      _shape(
        canvas,
        feather,
        near ? (i.isEven ? _gold : _teal) : (i.isEven ? _blue : _teal),
        outlined: true,
      );
    }

    if (near) {
      for (var row = 0; row < 2; row++) {
        for (var i = 0; i < 5; i++) {
          final x = 12.0 + i * 4.1;
          final y = -13.0 + row * 7;

          final covert = Path()
            ..moveTo(x - 2, y)
            ..quadraticBezierTo(x + 2, y - 5, x + 6, y - 1)
            ..quadraticBezierTo(x + 4, y + 5, x - 2, y)
            ..close();

          _shape(canvas, covert, row == 0 ? _cream : _gold);
        }
      }
    }

    canvas.restore();
  }

  void _drawBody(Canvas canvas) {
    final body = Path()
      ..moveTo(-12, -13)
      ..cubicTo(-18, 1, -14, 19, -4, 25)
      ..cubicTo(4, 30, 14, 21, 13, 9)
      ..cubicTo(12, -2, 7, -12, 1, -18)
      ..close();

    _shape(canvas, body, _gold, outlined: true);

    final breast = Path()
      ..moveTo(-5, -7)
      ..cubicTo(-10, 7, -6, 20, 2, 23)
      ..cubicTo(8, 17, 8, 1, 2, -8)
      ..close();

    _shape(canvas, breast, _cream);

    final neck = Path()
      ..moveTo(2, -12)
      ..cubicTo(7, -23, 4, -32, 11, -36)
      ..cubicTo(16, -39, 22, -35, 23, -30)
      ..cubicTo(16, -32, 13, -28, 14, -21)
      ..cubicTo(15, -15, 11, -10, 7, -7)
      ..close();

    _shape(canvas, neck, _gold, outlined: true);
  }

  void _drawHead(Canvas canvas) {
    const head = Offset(20, -34);

    canvas.drawCircle(head, 8.1, Paint()..color = _cream);
    canvas.drawCircle(head.translate(-1.4, 1.2), 6.6, Paint()..color = _gold);

    final beak = Path()
      ..moveTo(26, -36)
      ..cubicTo(35, -38, 38, -34, 33, -30)
      ..cubicTo(31, -28, 29, -29, 28, -31)
      ..close();

    _shape(canvas, beak, _teal);

    canvas.drawLine(
      const Offset(29, -32),
      const Offset(34, -33),
      Paint()
        ..color = _navy
        ..strokeWidth = 0.65,
    );

    final eyePaint = Paint()
      ..color = _navy
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    if (mood == SimorghMood.celebrating || mood == SimorghMood.gentle) {
      final eye = Path()
        ..moveTo(21.5, -35)
        ..quadraticBezierTo(
          23,
          mood == SimorghMood.celebrating ? -37 : -34,
          25,
          -35,
        );

      canvas.drawPath(eye, eyePaint);
    } else {
      final eyeY = mood == SimorghMood.thinking ? -36.5 : -35.0;

      canvas.drawCircle(Offset(23, eyeY), 2, Paint()..color = Colors.white);
      canvas.drawCircle(
        Offset(mood == SimorghMood.thinking ? 23.1 : 23.7, eyeY),
        1.15,
        Paint()..color = _navy,
      );
      canvas.drawCircle(
        Offset(24, eyeY - 0.45),
        0.35,
        Paint()..color = Colors.white,
      );
    }

    const crestColors = [_blue, _teal, _gold];

    for (var i = 0; i < 3; i++) {
      final x = 17.0 + i * 4.3;

      final crest = Path()
        ..moveTo(x - 2, -40)
        ..cubicTo(
          x - 8,
          -48 - i * 1.2,
          x - 2,
          -55 - i * 1.5,
          x + 1,
          -58 - i * 0.8,
        )
        ..cubicTo(x + 1, -51, x + 6, -47, x + 3, -40)
        ..close();

      _shape(canvas, crest, crestColors[i], outlined: true);
    }
  }

  void _drawFeet(Canvas canvas) {
    final paint = Paint()
      ..color = dark ? _cream : _navy
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    for (final x in const [-4.0, 6.0]) {
      canvas.drawLine(Offset(x, 23), Offset(x + 1, 29), paint);

      final claw = Path()
        ..moveTo(x + 1, 29)
        ..quadraticBezierTo(x - 2, 32, x - 5, 30);

      canvas.drawPath(claw, paint);
      canvas.drawLine(Offset(x + 1, 29), Offset(x + 4, 31), paint);
    }
  }

  void _drawSparks(Canvas canvas, double wave) {
    if (mood != SimorghMood.celebrating) return;

    final paint = Paint()..color = _gold.withValues(alpha: 0.85);

    for (final point in const [
      Offset(-38, -26),
      Offset(39, -20),
      Offset(0, -59),
    ]) {
      final center = point.translate(0, wave * 0.8);
      final radius = 1.6 + wave.abs() * 0.3;

      canvas.drawLine(
        center.translate(-radius, 0),
        center.translate(radius, 0),
        paint..strokeWidth = 1.2,
      );
      canvas.drawLine(
        center.translate(0, -radius),
        center.translate(0, radius),
        paint,
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || !size.width.isFinite || !size.height.isFinite) {
      return;
    }

    final rawPhase = animation?.value ?? phase;
    final safePhase = rawPhase.isFinite ? rawPhase : 0.5;
    final wave = math.sin(safePhase * math.pi * 2);

    final scale = math.min(size.width / 100, size.height / 124);

    final lift =
        wave * 2.5 +
        switch (mood) {
          SimorghMood.celebrating => -2.0,
          SimorghMood.thinking => 1.0,
          _ => 0.0,
        };

    canvas.save();
    canvas.translate(
      size.width / 2,
      size.height / 2 + 3 * scale + wave * scale,
    );
    canvas.scale(scale);

    final haloRect = Rect.fromCircle(center: Offset.zero, radius: 46);

    canvas.drawCircle(
      Offset.zero,
      46,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _gold.withValues(alpha: dark ? 0.16 : 0.20),
            _teal.withValues(alpha: 0.08),
            Colors.transparent,
          ],
        ).createShader(haloRect),
    );

    canvas.drawArc(
      Rect.fromCircle(center: Offset.zero, radius: 43),
      math.pi * 1.08,
      math.pi * 0.84,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = _gold.withValues(alpha: 0.3),
    );

    _drawTail(canvas, wave);
    _drawWing(canvas, near: false, lift: lift);
    _drawWing(canvas, near: true, lift: lift);
    _drawBody(canvas);
    _drawHead(canvas);
    _drawFeet(canvas);
    _drawSparks(canvas, wave);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SimorghCompanionPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.mood != mood ||
        oldDelegate.dark != dark ||
        oldDelegate.animation != animation;
  }
}
