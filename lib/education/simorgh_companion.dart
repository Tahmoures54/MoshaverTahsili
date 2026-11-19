import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ui.dart';

enum SimorghMood { welcome, thinking, encouraging, celebrating, gentle }

enum SimorghAction { planner, review, advisor }

enum SimorghChatState { listening, empathetic, thinking, happy, guiding }

extension SimorghChatStatePresentation on SimorghChatState {
  String get label => switch (this) {
    SimorghChatState.listening => 'با دقت گوش می‌دهم',
    SimorghChatState.empathetic => 'کنارت هستم تا مسئله را روشن کنیم',
    SimorghChatState.thinking => 'دارم پاسخ را آماده می‌کنم',
    SimorghChatState.happy => 'از پیشرفتت خوشحالم',
    SimorghChatState.guiding => 'بیایید قدم بعدی را پیدا کنیم',
  };

  SimorghMood get visualMood => switch (this) {
    SimorghChatState.listening => SimorghMood.welcome,
    SimorghChatState.empathetic => SimorghMood.gentle,
    SimorghChatState.thinking => SimorghMood.thinking,
    SimorghChatState.happy => SimorghMood.celebrating,
    SimorghChatState.guiding => SimorghMood.encouraging,
  };
}

/// The state is derived only from the visible conversation and request status.
/// It does not claim to detect or diagnose the student's emotions.
SimorghChatState resolveSimorghChatState({
  required bool busy,
  required List<Map<String, dynamic>> messages,
}) {
  if (busy) return SimorghChatState.thinking;
  if (messages.isEmpty) return SimorghChatState.listening;
  final last = messages.last;
  if (last['role'] == 'assistant') {
    final answer = last['content']?.toString() ?? '';
    if (RegExp(r'آفرین|پیشرفت|تبریک|تمام کردی|موفق شدی').hasMatch(answer)) {
      return SimorghChatState.happy;
    }
    return SimorghChatState.guiding;
  }
  final text = last['content']?.toString() ?? '';
  if (RegExp(r'نگران|می‌ترسم|میترسم|خسته|استرس|ناامید|غمگین|سخته|نمی‌توانم|نمی‌تونم')
      .hasMatch(text)) {
    return SimorghChatState.empathetic;
  }
  return SimorghChatState.listening;
}

/// Compact version of the same vector mascot, used in the dedicated chat header.
class SimorghChatAvatar extends StatelessWidget {
  const SimorghChatAvatar({super.key, required this.state});
  final SimorghChatState state;

  @override
  Widget build(BuildContext context) => Row(
    textDirection: TextDirection.rtl,
    children: [
      SizedBox(
        width: 62,
        height: 68,
        child: Semantics(
          label: 'حالت سیمرغ: ${state.label}',
          image: true,
          child: CustomPaint(
            key: const ValueKey('simorgh-chat-avatar'),
            painter: _SimorghCompanionPainter(
              phase: 0.5,
              mood: state.visualMood,
            ),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('سیمرغ', style: TextStyle(
              color: navy, fontSize: 16, fontWeight: FontWeight.w900,
            )),
            const SizedBox(height: 3),
            Text(state.label, style: const TextStyle(
              color: Color(0xFF42566B), fontSize: 12, height: 1.5,
            )),
            const SizedBox(height: 2),
            const Text('همراه یادگیری با کمک هوش مصنوعی', style: TextStyle(
              color: teal, fontSize: 10, fontWeight: FontWeight.w600,
            )),
          ],
        ),
      ),
    ],
  );
}

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

/// Selects a short, supportive prompt from facts already stored on the device.
/// It does not infer emotions, diagnose the student, or send data anywhere.
SimorghGuidance buildSimorghGuidance({
  required List<Map<String, dynamic>> tasks,
  required List<Map<String, dynamic>> cards,
  DateTime? now,
  String grade = '',
}) {
  final today = now ?? DateTime.now();
  final day = DateTime(today.year, today.month, today.day);

  final overdueTasks = tasks.where((task) {
    if (task['done'] == true) return false;
    final due = DateTime.tryParse(task['dueDate']?.toString() ?? '');
    return due != null && DateTime(due.year, due.month, due.day).isBefore(day);
  }).length;

  final dueCards = cards.where((card) {
    final due = DateTime.tryParse(card['dueAt']?.toString() ?? '');
    return due == null || !due.isAfter(today);
  }).length;

  final completedToday = tasks.where((task) {
    if (task['done'] != true) return false;
    final completedAt = DateTime.tryParse(task['completedAt']?.toString() ?? '');
    return completedAt != null &&
        completedAt.year == today.year &&
        completedAt.month == today.month &&
        completedAt.day == today.day;
  }).length;

  final pendingTasks = tasks.where((task) => task['done'] != true).length;
  final isPrimary = grade == 'ابتدایی';
  final isOlderStudent = grade == 'متوسطه دوم' || grade == 'دانش‌آموز کنکوری' || grade == 'دانشجو';

  if (overdueTasks > 0) {
    return SimorghGuidance(
      title: 'لازم نیست همه‌چیز را یک‌جا حل کنی',
      message: isPrimary
          ? '${faNumber(overdueTasks)} کار هنوز مانده. بیا یکی را با هم انتخاب کنیم و قدم‌به‌قدم پیش برویم.'
          : isOlderStudent
              ? '${faNumber(overdueTasks)} کار از برنامه عقب مانده است. یکی را اولویت‌بندی کن یا زمان‌بندی را واقع‌بینانه‌تر تنظیم کن.'
              : '${faNumber(overdueTasks)} کار از زمان برنامه‌ریزی‌شده گذشته. بیا یکی را انتخاب کنیم و اگر لازم بود برنامه را واقع‌بینانه‌تر بچینیم.',
      actionLabel: 'مرتب‌کردن برنامه',
      action: SimorghAction.planner,
      mood: SimorghMood.gentle,
    );
  }

  if (dueCards > 0) {
    return SimorghGuidance(
      title: 'وقت یک مرور کوتاه است',
      message: isPrimary
          ? '${faNumber(dueCards)} کارت برای مرور آماده است. بیا چندتایشان را با هم یادآوری کنیم.'
          : '${faNumber(dueCards)} فلش‌کارت برای مرور آماده است. چند دقیقه بازیابی از حافظه می‌تواند یادگیری را ماندگارتر کند.',
      actionLabel: 'شروع مرور',
      action: SimorghAction.review,
      mood: SimorghMood.thinking,
    );
  }

  if (completedToday > 0) {
    return SimorghGuidance(
      title: 'یک قدم واقعی برداشتی!',
      message: isPrimary
          ? 'آفرین! امروز ${faNumber(completedToday)} کار را تمام کردی. هر قدم کوچک ارزشمند است.'
          : 'امروز ${faNumber(completedToday)} کار را به پایان رساندی. همین پیشرفت‌های کوچک را حفظ کن؛ حالا می‌توانی برای قدم بعدی تصمیم بگیری.',
      actionLabel: 'دیدن برنامه',
      action: SimorghAction.planner,
      mood: SimorghMood.celebrating,
    );
  }

  if (tasks.isEmpty && cards.isEmpty) {
    return SimorghGuidance(
      title: isOlderStudent ? 'یک هدف روشن برای شروع انتخاب کن' : 'سفر یادگیری از یک قدم آغاز می‌شود',
      message: isPrimary
          ? 'هنوز برنامه‌ای ثبت نکرده‌ای. یک کار کوچک و دوست‌داشتنی انتخاب کنیم تا شروع کنیم.'
          : isOlderStudent
              ? 'هنوز برنامه یا فلش‌کارتی ثبت نکرده‌ای. یک هدف کوچک، مشخص و قابل‌اندازه‌گیری برای شروع تعیین کن.'
              : 'هنوز برنامه یا فلش‌کارتی ثبت نکرده‌ای. یک هدف کوچک و شدنی انتخاب کن؛ لازم نیست از همان اول همه‌چیز کامل باشد.',
      actionLabel: 'ساخت اولین برنامه',
      action: SimorghAction.planner,
      mood: SimorghMood.welcome,
    );
  }

  if (pendingTasks > 0) {
    return SimorghGuidance(
      title: 'قدم بعدی را خودت انتخاب کن',
      message: isPrimary
          ? '${faNumber(pendingTasks)} کار در برنامه‌ات مانده. از کاری شروع کن که کوتاه‌تر است.'
          : isOlderStudent
              ? '${faNumber(pendingTasks)} کار باز داری؛ قدم بعدی را بر اساس اهمیت و زمان لازم انتخاب کن.'
              : '${faNumber(pendingTasks)} کار ناتمام در برنامه‌ات داری. بهتر است از کاری شروع کنی که کوتاه‌تر یا برایت مهم‌تر است.',
      actionLabel: 'رفتن به برنامه',
      action: SimorghAction.planner,
      mood: SimorghMood.encouraging,
    );
  }

  return const SimorghGuidance(
    title: 'آماده یک هدف تازه‌ای؟',
    message: 'برنامه فعلی‌ات کار ناتمامی ندارد. اگر انرژی و زمان داری، یک هدف تازه و واقع‌بینانه برای خودت تعریف کن.',
    actionLabel: 'برنامه‌ریزی تازه',
    action: SimorghAction.planner,
    mood: SimorghMood.encouraging,
  );
}

/// A lightweight, vector-drawn companion. It uses no image or animation
/// package, keeping the mascot crisp at every density and inexpensive to ship.
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
  final bool active;

  @override
  State<SimorghCompanion> createState() => _SimorghCompanionState();
}

class _SimorghCompanionState extends State<SimorghCompanion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant SimorghCompanion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _syncAnimation();
  }

  void _syncAnimation() {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (!widget.active || reduceMotion) {
      _animation.stop();
      return;
    }
    if (_animation.status != AnimationStatus.forward) {
      _animation.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final guidance = buildSimorghGuidance(
      tasks: widget.tasks,
      cards: widget.cards,
      now: widget.now,
      grade: widget.grade,
    );
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFFFFFCF4), Color(0xFFEAF8F7)],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 100,
                  height: 116,
                  child: Semantics(
                    label: 'سیمرغ، همراه دانای مسیر یادگیری',
                    image: true,
                    child: TickerMode(
                      key: const ValueKey('simorgh-animation-ticker'),
                      enabled: widget.active && !reduceMotion,
                      child: AnimatedBuilder(
                        animation: _animation,
                        builder: (context, _) => CustomPaint(
                          key: const ValueKey('simorgh-character-painter'),
                          painter: _SimorghCompanionPainter(
                            phase: reduceMotion ? 0.5 : _animation.value,
                            mood: guidance.mood,
                          ),
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
                      const Text(
                        'همراه تو، سیمرغ',
                        style: TextStyle(
                          color: navy,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        guidance.title,
                        style: const TextStyle(
                          color: navy,
                          fontSize: 15,
                          height: 1.55,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        guidance.message,
                        style: const TextStyle(
                          color: Color(0xFF42566B),
                          fontSize: 12,
                          height: 1.75,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 6,
              children: [
                TextButton.icon(
                  onPressed: widget.onChat,
                  icon: const Icon(Icons.chat_bubble_outline, size: 17),
                  label: const Text('گفت‌وگو با مشاور'),
                ),
                FilledButton.tonal(
                  onPressed: () => widget.onAction(guidance.action),
                  style: FilledButton.styleFrom(
                    foregroundColor: navy,
                    backgroundColor: const Color(0xFFD5F0EB),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(guidance.actionLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SimorghCompanionPainter extends CustomPainter {
  const _SimorghCompanionPainter({required this.phase, required this.mood});

  final double phase;
  final SimorghMood mood;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = math.min(size.width, size.height).toDouble();
    final center = Offset(size.width * 0.5, size.height * 0.55);
    final bob = math.sin(phase * math.pi) * unit * 0.025;
    final wingLift = (math.sin(phase * math.pi * 2) * 0.12) +
        (mood == SimorghMood.celebrating ? -0.12 :
            mood == SimorghMood.thinking ? 0.05 :
            mood == SimorghMood.gentle ? 0.025 : 0.0);

    canvas.save();
    canvas.translate(0, bob);

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          simorghGold.withValues(alpha: 0.24),
          teal.withValues(alpha: 0.04),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: unit * 0.49));
    canvas.drawCircle(center, unit * 0.49, glowPaint);

    final leftWing = Path()
      ..moveTo(center.dx - unit * 0.10, center.dy - unit * 0.04)
      ..cubicTo(center.dx - unit * 0.34, center.dy - unit * (0.40 + wingLift),
          center.dx - unit * 0.52, center.dy - unit * (0.36 + wingLift),
          center.dx - unit * 0.43, center.dy - unit * 0.08)
      ..cubicTo(center.dx - unit * 0.35, center.dy - unit * 0.16,
          center.dx - unit * 0.30, center.dy - unit * 0.05,
          center.dx - unit * 0.22, center.dy + unit * 0.03)
      ..cubicTo(center.dx - unit * 0.31, center.dy - unit * 0.02,
          center.dx - unit * 0.31, center.dy + unit * 0.10,
          center.dx - unit * 0.19, center.dy + unit * 0.13)
      ..close();
    final rightWing = Path()
      ..moveTo(center.dx + unit * 0.10, center.dy - unit * 0.04)
      ..cubicTo(center.dx + unit * 0.34, center.dy - unit * (0.40 + wingLift),
          center.dx + unit * 0.52, center.dy - unit * (0.36 + wingLift),
          center.dx + unit * 0.43, center.dy - unit * 0.08)
      ..cubicTo(center.dx + unit * 0.35, center.dy - unit * 0.16,
          center.dx + unit * 0.30, center.dy - unit * 0.05,
          center.dx + unit * 0.22, center.dy + unit * 0.03)
      ..cubicTo(center.dx + unit * 0.31, center.dy - unit * 0.02,
          center.dx + unit * 0.31, center.dy + unit * 0.10,
          center.dx + unit * 0.19, center.dy + unit * 0.13)
      ..close();

    canvas.drawPath(leftWing, Paint()..color = simorghGold);
    canvas.drawPath(rightWing, Paint()..color = teal);

    final featherPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = unit * 0.018
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFFFE8B2).withValues(alpha: 0.9);
    for (var i = 0; i < 3; i++) {
      final offset = unit * (0.12 + i * 0.075);
      canvas.drawLine(
        Offset(center.dx - offset, center.dy - unit * 0.16),
        Offset(center.dx - offset * 1.65, center.dy - unit * 0.04),
        featherPaint,
      );
      canvas.drawLine(
        Offset(center.dx + offset, center.dy - unit * 0.16),
        Offset(center.dx + offset * 1.65, center.dy - unit * 0.04),
        Paint()
          ..color = const Color(0xFFB7F0E9)
          ..strokeWidth = unit * 0.018
          ..strokeCap = StrokeCap.round,
      );
    }

    final tail = Path()
      ..moveTo(center.dx - unit * 0.08, center.dy + unit * 0.20)
      ..quadraticBezierTo(center.dx - unit * 0.26, center.dy + unit * 0.43,
          center.dx - unit * 0.12, center.dy + unit * 0.45)
      ..quadraticBezierTo(center.dx + unit * 0.01, center.dy + unit * 0.36,
          center.dx + unit * 0.06, center.dy + unit * 0.24)
      ..close();
    canvas.drawPath(tail, Paint()..color = const Color(0xFF236B9A));

    final body = Path()
      ..moveTo(center.dx - unit * 0.13, center.dy - unit * 0.10)
      ..cubicTo(center.dx - unit * 0.20, center.dy + unit * 0.12,
          center.dx - unit * 0.10, center.dy + unit * 0.36,
          center.dx + unit * 0.06, center.dy + unit * 0.38)
      ..cubicTo(center.dx + unit * 0.25, center.dy + unit * 0.25,
          center.dx + unit * 0.24, center.dy - unit * 0.02,
          center.dx + unit * 0.10, center.dy - unit * 0.13)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF0C8), Color(0xFFF2BE58)],
        ).createShader(Rect.fromCircle(center: center, radius: unit * 0.4)),
    );

    final headCenter = Offset(center.dx + unit * 0.07, center.dy - unit * 0.18);
    canvas.drawCircle(headCenter, unit * 0.16, Paint()..color = simorghGold);
    final crest = Path()
      ..moveTo(headCenter.dx - unit * 0.06, headCenter.dy - unit * 0.12)
      ..quadraticBezierTo(headCenter.dx - unit * 0.22, headCenter.dy - unit * 0.36,
          headCenter.dx - unit * 0.02, headCenter.dy - unit * 0.27)
      ..quadraticBezierTo(headCenter.dx + unit * 0.02, headCenter.dy - unit * 0.39,
          headCenter.dx + unit * 0.09, headCenter.dy - unit * 0.25)
      ..quadraticBezierTo(headCenter.dx + unit * 0.18, headCenter.dy - unit * 0.31,
          headCenter.dx + unit * 0.15, headCenter.dy - unit * 0.12)
      ..close();
    canvas.drawPath(crest, Paint()..color = const Color(0xFF236B9A));

    final beak = Path()
      ..moveTo(headCenter.dx + unit * 0.12, headCenter.dy - unit * 0.01)
      ..lineTo(headCenter.dx + unit * 0.27, headCenter.dy + unit * 0.04)
      ..lineTo(headCenter.dx + unit * 0.11, headCenter.dy + unit * 0.09)
      ..close();
    canvas.drawPath(beak, Paint()..color = teal);

    final eye = Offset(
      headCenter.dx + unit * 0.065,
      headCenter.dy - unit * (mood == SimorghMood.thinking ? 0.055 :
          mood == SimorghMood.gentle ? 0.018 : 0.035),
    );
    final pupilShift = mood == SimorghMood.thinking ? -unit * 0.008 :
        mood == SimorghMood.celebrating ? unit * 0.004 : 0.0;
    canvas.drawCircle(eye, unit * 0.027, Paint()..color = Colors.white);
    canvas.drawCircle(eye.translate(unit * 0.008 + pupilShift, 0), unit * 0.014,
        Paint()..color = navy);
    canvas.drawCircle(eye.translate(unit * 0.012 + pupilShift, -unit * 0.006),
        unit * 0.004, Paint()..color = Colors.white);

    final smile = Path()
      ..moveTo(headCenter.dx + unit * 0.03, headCenter.dy + unit * 0.075)
      ..quadraticBezierTo(headCenter.dx + unit * 0.08,
          headCenter.dy + unit * (mood == SimorghMood.gentle ? 0.085 :
              mood == SimorghMood.thinking ? 0.095 : 0.13),
          headCenter.dx + unit * 0.13, headCenter.dy + unit * 0.07);
    canvas.drawPath(
      smile,
      Paint()
        ..color = navy.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = unit * 0.012
        ..strokeCap = StrokeCap.round,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SimorghCompanionPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.mood != mood;
}
