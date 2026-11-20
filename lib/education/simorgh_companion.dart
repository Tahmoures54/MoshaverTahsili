import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ui.dart';

enum SimorghMood { welcome, thinking, encouraging, celebrating, gentle }

enum SimorghAction { planner, review, advisor }

enum SimorghChatState { listening, empathetic, thinking, happy, guiding }

extension SimorghChatStatePresentation on SimorghChatState {
  String get label => switch (this) {
    SimorghChatState.listening => 'شنونده · با دقت گوش می‌دهم',
    SimorghChatState.empathetic => 'همدل · با هم مسئله را روشن کنیم',
    SimorghChatState.thinking => 'متفکر · دارم پاسخ را آماده می‌کنم',
    SimorghChatState.happy => 'خوشحال · پیشرفتت ارزشمند است',
    SimorghChatState.guiding => 'راهنما · بیایید قدم بعدی را پیدا کنیم',
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
      duration: const Duration(milliseconds: 2600),
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
    if (!_animation.isAnimating) {
      _animation.repeat(reverse: false);
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

/// A mythic Persian Simorgh: broad eagle-like wings, a proud curved neck,
/// a three-plume crown and long jewel-toned tail feathers. All geometry is
/// vector-drawn so it stays crisp without adding image assets or dependencies.
class _SimorghCompanionPainter extends CustomPainter {
  const _SimorghCompanionPainter({required this.phase, required this.mood});

  final double phase;
  final SimorghMood mood;

  static const _navy = Color(0xFF142D4E);
  static const _blue = Color(0xFF236B9A);
  static const _teal = Color(0xFF20B8AE);
  static const _gold = Color(0xFFF2BE58);
  static const _cream = Color(0xFFFFF1D0);
  static const _deepTeal = Color(0xFF087F83);

  void _feather(Canvas canvas, Path path, Color color, {Color? edge}) {
    canvas.drawPath(path, Paint()..color = color);
    if (edge != null) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9
          ..color = edge.withValues(alpha: 0.72),
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final s = math.min(size.width / 100, size.height / 116);
    final origin = Offset(size.width * 0.5, size.height * 0.53);
    final flap = math.sin(phase * math.pi * 2);
    final lift = flap * 3.2 +
        (mood == SimorghMood.celebrating ? -2.5 : 0) +
        (mood == SimorghMood.thinking ? 1.2 : 0);
    final bob = math.sin(phase * math.pi * 2) * 1.2;

    canvas.save();
    canvas.translate(origin.dx, origin.dy + bob * s);
    canvas.scale(s);

    // A restrained halo gives the bird a legendary, luminous presence.
    canvas.drawCircle(
      Offset.zero,
      47,
      Paint()
        ..shader = RadialGradient(
          colors: [
            _gold.withValues(alpha: 0.20),
            _teal.withValues(alpha: 0.08),
            Colors.transparent,
          ],
        ).createShader(const Rect.fromCircle(center: Offset.zero, radius: 47)),
    );
    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = _gold.withValues(alpha: 0.25);
    canvas.drawArc(
      const Rect.fromCircle(center: Offset(0, 0), radius: 43),
      math.pi * 1.08,
      math.pi * 0.84,
      false,
      halo,
    );

    // Long, separated tail streamers: a key silhouette absent from the old
    // round-bodied bird. The central plume carries the Simorgh jewel motif.
    final tailColors = [_blue, _deepTeal, _gold, _teal, _blue];
    for (var i = 0; i < 5; i++) {
      final x = (i - 2) * 7.0;
      final sway = flap * (i.isEven ? 1.5 : -1.5);
      final tail = Path()
        ..moveTo(-5 + x * 0.18, 17)
        ..cubicTo(x - 8 + sway, 34, x + 11 + sway, 43, x + sway, 53 - (i == 2 ? 5 : 0))
        ..cubicTo(x - 5 + sway, 45, x - 9 + sway, 34, -2 + x * 0.2, 18)
        ..close();
      _feather(canvas, tail, tailColors[i]);
      canvas.drawLine(
        Offset(-2 + x * 0.2, 19),
        Offset(x + sway, 48),
        Paint()
          ..color = _cream.withValues(alpha: 0.55)
          ..strokeWidth = 0.8
          ..strokeCap = StrokeCap.round,
      );
    }
    // Jewel/eye at the end of the central tail feather.
    canvas.drawCircle(const Offset(0, 46), 3.4, Paint()..color = _gold);
    canvas.drawCircle(const Offset(0, 46), 1.7, Paint()..color = _teal);

    // Far wing first, with individually readable flight feathers.
    final farWing = Path()
      ..moveTo(-7, -4)
      ..cubicTo(-24, -19 - lift, -39, -42 - lift, -47, -39 - lift * 0.55)
      ..cubicTo(-49, -26, -39, -13, -28, -7)
      ..cubicTo(-38, -10, -39, 1, -27, 7)
      ..cubicTo(-34, 7, -32, 16, -20, 17)
      ..cubicTo(-15, 8, -10, 2, -7, -4)
      ..close();
    _feather(canvas, farWing, _deepTeal);
    for (var i = 0; i < 6; i++) {
      final x = -43.0 + i * 4.2;
      final feather = Path()
        ..moveTo(-13, -1 + i * 2.0)
        ..cubicTo(x - 4, -18 - lift, x - 4, -36 - lift * 0.55, x + 1, -39 - lift * 0.55)
        ..cubicTo(x + 8, -26 - lift * 0.4, x + 5, -12, -8 + i * 1.0, 7)
        ..close();
      _feather(canvas, feather, i.isEven ? _blue : _teal, edge: _cream);
    }

    // Near wing is broad and layered like a great bird's wing, not a tiny
    // pair of decorative triangles.
    final nearWing = Path()
      ..moveTo(5, -7)
      ..cubicTo(20, -24 - lift, 35, -47 - lift, 47, -41 - lift * 0.6)
      ..cubicTo(50, -29, 40, -15, 29, -7)
      ..cubicTo(39, -11, 40, 0, 28, 8)
      ..cubicTo(35, 8, 32, 17, 19, 18)
      ..cubicTo(13, 8, 8, 1, 5, -7)
      ..close();
    _feather(canvas, nearWing, _blue);
    for (var i = 0; i < 7; i++) {
      final x = 39.0 - i * 4.3;
      final feather = Path()
        ..moveTo(12, -3 + i * 1.8)
        ..cubicTo(x + 4, -19 - lift, x + 5, -37 - lift * 0.55, x - 1, -41 - lift * 0.55)
        ..cubicTo(x - 9, -26 - lift * 0.4, x - 6, -12, 7 - i * 0.8, 8)
        ..close();
      _feather(canvas, feather, i.isEven ? _gold : _teal, edge: _cream);
    }
    // Wing coverts create a layered, ornamental pattern.
    for (var row = 0; row < 2; row++) {
      for (var i = 0; i < 5; i++) {
        final x = 12.0 + i * 4.1;
        final y = -13.0 + row * 7;
        final covert = Path()
          ..moveTo(x - 2, y)
          ..quadraticBezierTo(x + 2, y - 5, x + 6, y - 1)
          ..quadraticBezierTo(x + 4, y + 5, x - 2, y)
          ..close();
        _feather(canvas, covert, row == 0 ? _cream : _gold);
      }
    }

    // Body: tapered, proud and upright, with a long S-shaped neck.
    final body = Path()
      ..moveTo(-12, -13)
      ..cubicTo(-18, 1, -14, 19, -4, 25)
      ..cubicTo(4, 30, 14, 21, 13, 9)
      ..cubicTo(12, -2, 7, -12, 1, -18)
      ..close();
    _feather(
      canvas,
      body,
      const Color(0xFFEDB94E),
      edge: const Color(0xFFFFE6A5),
    );
    final breast = Path()
      ..moveTo(-5, -7)
      ..cubicTo(-10, 7, -6, 20, 2, 23)
      ..cubicTo(8, 17, 8, 1, 2, -8)
      ..close();
    _feather(canvas, breast, _cream);

    final neck = Path()
      ..moveTo(2, -12)
      ..cubicTo(7, -23, 4, -32, 11, -36)
      ..cubicTo(16, -39, 22, -35, 23, -30)
      ..cubicTo(16, -32, 13, -28, 14, -21)
      ..cubicTo(15, -15, 11, -10, 7, -7)
      ..close();
    _feather(canvas, neck, _gold, edge: _cream);

    // Head faces right, with a hooked golden beak and alert eye.
    final head = Offset(20, -34);
    canvas.drawCircle(head, 8.1, Paint()..color = _cream);
    canvas.drawCircle(
      head.translate(-1.4, 1.2),
      6.6,
      Paint()..color = _gold.withValues(alpha: 0.8),
    );
    final beak = Path()
      ..moveTo(26, -36)
      ..cubicTo(35, -38, 38, -34, 33, -30)
      ..cubicTo(31, -28, 29, -29, 28, -31)
      ..close();
    _feather(canvas, beak, _teal);
    canvas.drawLine(
      const Offset(29, -32),
      const Offset(34, -33),
      Paint()
        ..color = _navy.withValues(alpha: 0.55)
        ..strokeWidth = 0.65,
    );
    final eyeY = mood == SimorghMood.thinking ? -37.0 : -35.0;
    canvas.drawCircle(const Offset(23, eyeY), 2.0, Paint()..color = Colors.white);
    canvas.drawCircle(const Offset(23.7, eyeY), 1.15, Paint()..color = _navy);
    canvas.drawCircle(const Offset(24, eyeY - 0.45), 0.35, Paint()..color = Colors.white);

    // Three rising crown plumes, an unmistakable royal silhouette.
    final crestColors = [_blue, _teal, _gold];
    for (var i = 0; i < 3; i++) {
      final x = 17.0 + i * 4.3;
      final crest = Path()
        ..moveTo(x - 2, -40)
        ..cubicTo(x - 8, -48 - i * 1.2, x - 2, -55 - i * 1.5, x + 1, -58 - i * 0.8)
        ..cubicTo(x + 1, -51, x + 6, -47, x + 3, -40)
        ..close();
      _feather(canvas, crest, crestColors[i], edge: _cream);
    }

    // Small feet and curved talons anchor the silhouette.
    final legs = Paint()
      ..color = _navy
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    for (final x in [-4.0, 6.0]) {
      canvas.drawLine(Offset(x, 23), Offset(x + 1, 29), legs);
      final claw = Path()
        ..moveTo(x + 1, 29)
        ..quadraticBezierTo(x - 2, 32, x - 5, 30);
      canvas.drawPath(claw, legs);
      canvas.drawLine(Offset(x + 1, 29), Offset(x + 4, 31), legs);
    }

    // Tiny floating sparks respond to the celebratory mood.
    if (mood == SimorghMood.celebrating) {
      final sparkPaint = Paint()..color = _gold.withValues(alpha: 0.9);
      for (final p in const [Offset(-39, -25), Offset(39, -20), Offset(0, -62)]) {
        canvas.drawCircle(p, 1.5, sparkPaint);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SimorghCompanionPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.mood != mood;
}
