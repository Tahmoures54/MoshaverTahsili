import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// اورلی لودینگ عیب‌یابی — سرگرم‌کننده تا کاربر فکر نکند اپ هنگ کرده
class DiagnoseLoadingOverlay extends StatefulWidget {
  final bool visible;
  final String? customMessage;

  const DiagnoseLoadingOverlay({
    super.key,
    required this.visible,
    this.customMessage,
  });

  @override
  State<DiagnoseLoadingOverlay> createState() => _DiagnoseLoadingOverlayState();
}

class _DiagnoseLoadingOverlayState extends State<DiagnoseLoadingOverlay>
    with TickerProviderStateMixin {
  // نکات سرگرم‌کننده و مفید (تم مکانیکی)
  static const _tips = <String>[
    '🔧 دارم صدای موتور رو توی ذهنم می‌شنوم…',
    '⚙️ مقایسه با هزاران الگوی خرابی مشابه…',
    '🛢️ چک کردن احتمال نشتی روغن و واشرها…',
    '🔋 بررسی سیستم برق و سنسورها…',
    '🛠️ آماده‌سازی راهنمای گام‌به‌گام…',
    '🚗 گاهی یه پیچ شل، کل ماجراست!',
    '💡 نکته: صدای تق‌تق موقع استارت اغلب از استارت یا باتریه',
    '🌡️ دمای بیش از حد؟ رادیاتور و ترموستات رو چک کن',
    '🔍 دارم احتمال خرابی تسمه تایمینگ رو می‌سنجم…',
    '🎯 تقریباً تموم شد — دارم نتیجه رو مرتب می‌کنم',
  ];

  static const _stages = <_Stage>[
    _Stage('خواندن شرح مشکل', Icons.description_rounded),
    _Stage('تحلیل علائم', Icons.analytics_rounded),
    _Stage('مقایسه الگوها', Icons.compare_arrows_rounded),
    _Stage('ساخت راهنما', Icons.handyman_rounded),
  ];

  int _tipIndex = 0;
  int _stageIndex = 0;
  int _elapsedSec = 0;
  Timer? _tipTimer;
  Timer? _stageTimer;
  Timer? _clockTimer;

  late final AnimationController _spinCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _gearCtrl;

  @override
  void initState() {
    super.initState();
    // Keep controllers idle while the overlay is hidden. Repeating tickers
    // needlessly consume frame work on every screen that hosts this widget.
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _gearCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );

    if (widget.visible) _start();
  }

  @override
  void didUpdateWidget(covariant DiagnoseLoadingOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) {
      _start();
    } else if (!widget.visible && oldWidget.visible) {
      _stop();
    }
  }

  void _start() {
    _tipIndex = 0;
    _stageIndex = 0;
    _elapsedSec = 0;

    // Start animations only while the loading overlay is visible.
    _spinCtrl.repeat();
    _pulseCtrl.repeat(reverse: true);
    _gearCtrl.repeat();

    _tipTimer?.cancel();
    _stageTimer?.cancel();
    _clockTimer?.cancel();

    _tipTimer = Timer.periodic(const Duration(milliseconds: 3200), (_) {
      if (!mounted) return;
      setState(() => _tipIndex = (_tipIndex + 1) % _tips.length);
    });

    // مراحل پیشرفت ظاهری — حس پیشرفت واقعی می‌دهد
    _stageTimer = Timer.periodic(const Duration(milliseconds: 4500), (_) {
      if (!mounted) return;
      setState(() {
        if (_stageIndex < _stages.length - 1) _stageIndex++;
      });
    });

    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSec++);
    });
  }

  void _stop() {
    _tipTimer?.cancel();
    _stageTimer?.cancel();
    _clockTimer?.cancel();

    // Stop all repeating tickers as soon as the overlay becomes hidden.
    _spinCtrl.stop();
    _pulseCtrl.stop();
    _gearCtrl.stop();

    _tipTimer = null;
    _stageTimer = null;
    _clockTimer = null;
    _tipIndex = 0;
    _stageIndex = 0;
    _elapsedSec = 0;
  }

  @override
  void dispose() {
    _stop();
    _spinCtrl.dispose();
    _pulseCtrl.dispose();
    _gearCtrl.dispose();
    super.dispose();
  }

  String get _elapsedLabel {
    if (_elapsedSec < 60) return '$_elapsedSec ثانیه';
    final m = _elapsedSec ~/ 60;
    final s = _elapsedSec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox.shrink();

    final tip = widget.customMessage ?? _tips[_tipIndex];
    final theme = Theme.of(context);

    return Positioned.fill(
      child: AbsorbPointer(
        child: Container(
          color: Colors.black.withOpacity(0.78),
          alignment: Alignment.center,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
            decoration: BoxDecoration(
              color: const Color(0xFF1A120E),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.orange.withOpacity(0.4)),
              boxShadow: [
                BoxShadow(
                  color: Colors.orange.withOpacity(0.18),
                  blurRadius: 40,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── انیمیشن آچار + چرخ‌دنده‌ها ──
                SizedBox(
                  height: 88,
                  width: 120,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // چرخ‌دنده چپ
                      Positioned(
                        left: 4,
                        child: AnimatedBuilder(
                          animation: _gearCtrl,
                          builder: (_, __) => Transform.rotate(
                            angle: _gearCtrl.value * 2 * math.pi,
                            child: Icon(
                              Icons.settings_rounded,
                              size: 36,
                              color: Colors.orange.withOpacity(0.55),
                            ),
                          ),
                        ),
                      ),
                      // چرخ‌دنده راست (جهت مخالف)
                      Positioned(
                        right: 4,
                        child: AnimatedBuilder(
                          animation: _gearCtrl,
                          builder: (_, __) => Transform.rotate(
                            angle: -_gearCtrl.value * 2 * math.pi * 0.7,
                            child: Icon(
                              Icons.settings_rounded,
                              size: 28,
                              color: Colors.deepOrange.withOpacity(0.45),
                            ),
                          ),
                        ),
                      ),
                      // آچار چرخان با پالس
                      AnimatedBuilder(
                        animation: Listenable.merge([_spinCtrl, _pulseCtrl]),
                        builder: (_, __) {
                          final scale = 0.92 + (_pulseCtrl.value * 0.12);
                          return Transform.scale(
                            scale: scale,
                            child: Transform.rotate(
                              angle: _spinCtrl.value * 2 * math.pi,
                              child: Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      Colors.orange.withOpacity(0.35),
                                      Colors.orange.withOpacity(0.05),
                                    ],
                                  ),
                                  border: Border.all(
                                    color: Colors.orange.withOpacity(0.6),
                                    width: 2.5,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.build_rounded,
                                  size: 32,
                                  color: Colors.orange,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                Text(
                  'در حال عیب‌یابی…',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.amber.shade50,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                ),

                const SizedBox(height: 14),

                // ── مراحل پیشرفت ──
                _buildStages(),

                const SizedBox(height: 16),

                // ── نکته چرخشی ──
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 420),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.15),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: Text(
                    tip,
                    key: ValueKey(tip),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.amber.shade100.withOpacity(0.85),
                      height: 1.55,
                      fontSize: 13.5,
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ── تایمر + توضیحه ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.timer_outlined,
                      size: 14,
                      color: Colors.amber.shade100.withOpacity(0.45),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _elapsedLabel,
                      style: TextStyle(
                        color: Colors.amber.shade100.withOpacity(0.5),
                        fontSize: 12,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '·',
                      style: TextStyle(
                        color: Colors.amber.shade100.withOpacity(0.3),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        'معمولاً ۱۰ تا ۴۰ ثانیه',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.amber.shade100.withOpacity(0.4),
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStages() {
    return Row(
      children: List.generate(_stages.length * 2 - 1, (i) {
        if (i.isOdd) {
          // خط اتصال
          final leftDone = (i ~/ 2) < _stageIndex;
          return Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: leftDone
                    ? Colors.orange.withOpacity(0.7)
                    : Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          );
        }

        final idx = i ~/ 2;
        final done = idx < _stageIndex;
        final active = idx == _stageIndex;
        final stage = _stages[idx];

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              width: active ? 30 : 24,
              height: active ? 30 : 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done
                    ? Colors.orange
                    : active
                        ? Colors.orange.withOpacity(0.25)
                        : Colors.white.withOpacity(0.08),
                border: Border.all(
                  color: done || active
                      ? Colors.orange
                      : Colors.white.withOpacity(0.2),
                  width: active ? 2 : 1.5,
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: Colors.orange.withOpacity(0.4),
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                done ? Icons.check_rounded : stage.icon,
                size: active ? 15 : 12,
                color: done
                    ? Colors.black87
                    : active
                        ? Colors.orange
                        : Colors.white38,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 58,
              child: Text(
                stage.label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  color: done || active
                      ? Colors.amber.shade100.withOpacity(0.75)
                      : Colors.white30,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _Stage {
  final String label;
  final IconData icon;
  const _Stage(this.label, this.icon);
}
