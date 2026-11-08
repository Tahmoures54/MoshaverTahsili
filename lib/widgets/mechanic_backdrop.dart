import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/brand.dart';

/// پس‌زمینهٔ تمام‌صفحه با حس کارگاه: نور نارنجی، کف تعمیرگاه، چرخ‌دنده
class MechanicBackdrop extends StatelessWidget {
  const MechanicBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: CustomPaint(
        painter: _GaragePainter(dark: dark),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _GaragePainter extends CustomPainter {
  final bool dark;

  _GaragePainter({required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final base = dark ? BrandColors.darkBackground : BrandColors.lightBackground;
    canvas.drawRect(Offset.zero & size, Paint()..color = base);

    final lamp = RadialGradient(
      center: const Alignment(0.85, -0.95),
      radius: 1.15,
      colors: dark
          ? [
              BrandColors.orange.withOpacity(0.42),
              BrandColors.orangeDeep.withOpacity(0.16),
              Colors.transparent,
            ]
          : [
              BrandColors.orange.withOpacity(0.28),
              BrandColors.orangeLight.withOpacity(0.18),
              Colors.transparent,
            ],
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = lamp.createShader(Offset.zero & size),
    );

    final floor = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: dark
          ? [
              Colors.transparent,
              BrandColors.rust.withOpacity(0.18),
              const Color(0xFF0A0604),
            ]
          : [
              Colors.transparent,
              BrandColors.orange.withOpacity(0.08),
              BrandColors.orangeLight.withOpacity(0.35),
            ],
    );
    canvas.drawRect(
      Offset.zero & size,
      Paint()..shader = floor.createShader(Offset.zero & size),
    );

    final hatch = Paint()
      ..color = (dark ? BrandColors.orange : BrandColors.orangeDeep)
          .withOpacity(dark ? 0.045 : 0.06)
      ..strokeWidth = 1;
    const gap = 28.0;
    for (double x = -size.height; x < size.width + size.height; x += gap) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        hatch,
      );
    }

    _gear(
      canvas,
      Offset(size.width * 0.08, size.height * 0.18),
      size.width * 0.22,
      dark,
    );
    _gear(
      canvas,
      Offset(size.width * 0.92, size.height * 0.78),
      size.width * 0.28,
      dark,
    );

    final glowLine = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          BrandColors.orange.withOpacity(dark ? 0.55 : 0.4),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 3));
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 3), glowLine);
  }

  void _gear(Canvas canvas, Offset c, double r, bool isDark) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = BrandColors.orange.withOpacity(isDark ? 0.09 : 0.11);
    canvas.drawCircle(c, r, paint);
    canvas.drawCircle(c, r * 0.62, paint);
    canvas.drawCircle(c, r * 0.18, paint);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * (r * 0.62),
        c + Offset(math.cos(a), math.sin(a)) * r,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GaragePainter oldDelegate) =>
      oldDelegate.dark != dark;
}
