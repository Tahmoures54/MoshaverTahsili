import 'package:flutter/material.dart';

import 'ai_advisor_service.dart';
import 'bazaar_billing_service.dart';
import 'education_store.dart';

const navy = Color(0xFF142D4E);
const blue = Color(0xFF236B9A);
const teal = Color(0xFF20B8AE);
const pale = Color(0xFFF5F8FC);
const simorghGold = Color(0xFFF2BE58);

const _persianDigits = '۰۱۲۳۴۵۶۷۸۹';
const _arabicDigits = '٠١٢٣٤٥٦٧٨٩';

/// Converts ASCII and Arabic-Indic digits to Persian digits for display.
String faNumber(Object? value) {
  var text = value?.toString() ?? '';

  for (var i = 0; i < 10; i++) {
    text = text
        .replaceAll(i.toString(), _persianDigits[i])
        .replaceAll(_arabicDigits[i], _persianDigits[i]);
  }

  return text;
}

/// Normalizes Persian/Arabic digits and common numeric separators.
///
/// Examples:
/// ۱۲٫۵   -> 12.5
/// ۱٬۲۵۰  -> 1250
/// 1,250  -> 1250
/// ۱۲،۵   -> 12.5
///
/// Ambiguous comma-separated values such as "1,250" are treated as grouped
/// integers. Use a dot or Arabic decimal separator for an explicit decimal.
String digitsToEnglish(String value) {
  var result = value.trim();

  for (var i = 0; i < 10; i++) {
    result = result
        .replaceAll(_persianDigits[i], i.toString())
        .replaceAll(_arabicDigits[i], i.toString());
  }

  result = result
      .replaceAll('٫', '.')
      .replaceAll('٬', '')
      .replaceAll('،', ',')
      .replaceAll('−', '-')
      .replaceAll(RegExp(r'[\s\u00A0\u202F\u200E\u200F\u061C]'), '');

  // Supports grouped integers and grouped numbers with a decimal part.
  final grouped = RegExp(r'^[-+]?\d{1,3}(,\d{3})+(\.\d+)?$');

  if (grouped.hasMatch(result)) {
    return result.replaceAll(',', '');
  }

  // One comma without a dot may be a decimal separator.
  // Leave malformed input unchanged so numeric parsers can reject it.
  if (!result.contains('.') && ','.allMatches(result).length == 1) {
    return result.replaceAll(',', '.');
  }

  return result;
}

/// Keeps known, user-safe application errors and hides unexpected internals.
String friendlyError(Object error) {
  if (error is AiException ||
      error is LocalDataException ||
      error is BillingException) {
    final message = error.toString().trim();

    if (message.isNotEmpty) {
      return message;
    }
  }

  return 'این عملیات کامل نشد. فضای خالی گوشی و اتصال اینترنت '
      'را بررسی کن و دوباره تلاش کن.';
}

void showMessage(BuildContext context, String message) {
  if (!context.mounted) return;

  final text = message.trim();
  if (text.isEmpty) return;

  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text, maxLines: 4, overflow: TextOverflow.ellipsis),
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
      ),
    );
}

ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: navy,
    primary: navy,
    secondary: teal,
    tertiary: simorghGold,
    surface: const Color(0xFFFCFDFE),
    brightness: Brightness.light,
  );

  final base = ThemeData(
    useMaterial3: true,
    fontFamily: 'Vazirmatn',
    colorScheme: scheme,
    scaffoldBackgroundColor: pale,
    visualDensity: VisualDensity.standard,
  );

  // Derive customized styles from the already font-applied theme.
  // Using base styles from before apply() would discard the custom font.
  final fontTheme = base.textTheme.apply(
    fontFamily: 'Vazirmatn',
    bodyColor: navy,
    displayColor: navy,
  );

  final textTheme = fontTheme.copyWith(
    headlineSmall: fontTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w800,
      height: 1.45,
    ),
    titleLarge: fontTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w800,
      height: 1.45,
    ),
    titleMedium: fontTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
      height: 1.5,
    ),
    bodyLarge: fontTheme.bodyLarge?.copyWith(height: 1.8),
    bodyMedium: fontTheme.bodyMedium?.copyWith(height: 1.75),
    labelLarge: fontTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
  );

  return base.copyWith(
    textTheme: textTheme,
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: 'Vazirmatn'),
    appBarTheme: const AppBarTheme(
      backgroundColor: pale,
      foregroundColor: navy,
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 1,
      titleTextStyle: TextStyle(
        fontFamily: 'Vazirmatn',
        color: navy,
        fontSize: 18,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE3EAF2)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFD8E2ED)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFD8E2ED)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: teal, width: 1.7),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFB3261E)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFB3261E), width: 1.7),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      elevation: 0,
      indicatorColor: teal.withValues(alpha: .16),
      labelTextStyle: WidgetStatePropertyAll<TextStyle?>(
        textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: teal,
        foregroundColor: navy,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        textStyle: const TextStyle(
          fontFamily: 'Vazirmatn',
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: navy,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: const TextStyle(
          fontFamily: 'Vazirmatn',
          fontWeight: FontWeight.w700,
        ),
        side: const BorderSide(color: Color(0xFFD5E0EA)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: navy,
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(
          fontFamily: 'Vazirmatn',
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: navy,
      contentTextStyle: TextStyle(
        fontFamily: 'Vazirmatn',
        color: Colors.white,
        height: 1.6,
      ),
      closeIconColor: Colors.white,
      behavior: SnackBarBehavior.floating,
      showCloseIcon: true,
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFFE5EBF1),
      thickness: 1,
      space: 1,
    ),
    chipTheme: base.chipTheme.copyWith(
      labelStyle: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: teal,
      linearTrackColor: Color(0xFFE5EEF3),
    ),
  );
}

/// Shared brand components. Keep the mascot expressive while learning content
/// remains the visual priority on small screens.
class SimorghHomeHero extends StatelessWidget {
  const SimorghHomeHero({
    super.key,
    required this.nickname,
    required this.gradeLine,
    required this.onChat,
  });

  final String nickname;
  final String gradeLine;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final name = nickname.trim();
    final grade = gradeLine.trim();

    final greeting = name.isEmpty ? 'درود بر جوینده دانایی!' : 'درود، $name!';

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;

        final stacked = constraints.maxWidth < 280 || textScale > 1.5;

        final markSize = compact ? 62.0 : 76.0;

        final introduction = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              greeting,
              style: TextStyle(
                color: const Color(0xFFFFE8B2),
                fontSize: compact ? 16 : 19,
                fontWeight: FontWeight.w900,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'همراه دانای راه آینده',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.6,
              ),
            ),
            if (grade.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(
                grade,
                style: const TextStyle(
                  color: Color(0xFFD9E7F2),
                  fontSize: 11,
                  height: 1.6,
                ),
              ),
            ],
          ],
        );

        return Container(
          width: double.infinity,
          padding: EdgeInsets.all(compact ? 14 : 18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFF1D4770), Color(0xFF142D4E), Color(0xFF10233F)],
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: simorghGold.withValues(alpha: .42)),
            boxShadow: [
              BoxShadow(
                color: navy.withValues(alpha: .12),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (stacked)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SimorghMark(size: markSize, compact: true),
                    const SizedBox(height: 12),
                    introduction,
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SimorghMark(size: markSize, compact: true),
                    SizedBox(width: compact ? 10 : 14),
                    Expanded(child: introduction),
                  ],
                ),
              const SizedBox(height: 14),
              const Text(
                'من مسیر را روشن‌تر می‌کنم؛ پرواز را خودت '
                'انجام می‌دهی. امروز با یک قدم کوچک شروع کنیم.',
                style: TextStyle(
                  color: Colors.white,
                  height: 1.8,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.icon(
                  onPressed: onChat,
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('گفت‌وگو با سیمرغ'),
                  style: FilledButton.styleFrom(
                    backgroundColor: simorghGold,
                    foregroundColor: navy,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class SimorghSectionTitle extends StatelessWidget {
  const SimorghSectionTitle({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final description = subtitle?.trim() ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 22,
                decoration: BoxDecoration(
                  color: teal,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: navy,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 13),
              child: Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF617387),
                  height: 1.6,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class NoticeCard extends StatelessWidget {
  const NoticeCard({
    super.key,
    required this.text,
    this.icon = Icons.info_outline,
    this.warning = false,
  });

  final String text;
  final IconData icon;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final background = warning
        ? const Color(0xFFFFF5E5)
        : const Color(0xFFEAF6F4);

    final foreground = warning ? const Color(0xFF8A4B12) : navy;

    return Card(
      color: background,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Icon(
                warning && icon == Icons.info_outline
                    ? Icons.warning_amber_rounded
                    : icon,
                size: 21,
                color: warning ? const Color(0xFFB65D19) : teal,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                text,
                style: TextStyle(color: foreground, height: 1.8, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SimorghFeatherMark extends StatelessWidget {
  const SimorghFeatherMark({super.key, this.size = 28})
    : assert(size > 0 && size < double.infinity);

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'پر سیمرغ',
    child: ExcludeSemantics(
      child: SizedBox(
        width: size,
        height: size * 1.15,
        child: CustomPaint(painter: _SimorghFeatherPainter()),
      ),
    ),
  );
}

class _SimorghFeatherPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final feather = Path()
      ..moveTo(size.width * .15, size.height * .88)
      ..cubicTo(
        size.width * .12,
        size.height * .55,
        size.width * .30,
        size.height * .16,
        size.width * .84,
        size.height * .08,
      )
      ..cubicTo(
        size.width * .82,
        size.height * .49,
        size.width * .61,
        size.height * .79,
        size.width * .15,
        size.height * .88,
      )
      ..close();

    canvas.drawPath(feather, Paint()..color = simorghGold);

    final shaft = Paint()
      ..color = navy.withValues(alpha: .72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .045
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(size.width * .13, size.height * .90),
      Offset(size.width * .85, size.height * .07),
      shaft,
    );

    for (var index = 1; index <= 4; index++) {
      final t = index / 6;
      final x = size.width * (.13 + .72 * t);
      final y = size.height * (.90 - .83 * t);

      canvas.drawLine(
        Offset(x, y),
        Offset(x - size.width * .13, y + size.height * .035),
        shaft,
      );

      canvas.drawLine(
        Offset(x, y),
        Offset(x + size.width * .08, y + size.height * .025),
        shaft,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SimorghFeatherPainter oldDelegate) => false;
}

class CreditSummary extends StatelessWidget {
  const CreditSummary({super.key, required this.store, this.onShop});

  final EducationStore store;
  final VoidCallback? onShop;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      final walletError = store.walletError;

      if (walletError != null) {
        return NoticeCard(text: walletError, warning: true);
      }

      final remainingFree = store.freeAiUsesRemaining;
      final feathers = store.feathers;

      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;

              final stacked = constraints.maxWidth < 280 || textScale > 1.4;

              final balance = Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SimorghFeatherMark(size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'پرهای سیمرغ',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${faNumber(feathers)} پر',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (stacked) ...[
                    balance,
                    if (onShop != null) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: FilledButton.tonal(
                          onPressed: onShop,
                          child: const Text('تهیه پر'),
                        ),
                      ),
                    ],
                  ] else
                    Row(
                      children: [
                        Expanded(child: balance),
                        if (onShop != null) ...[
                          const SizedBox(width: 12),
                          FilledButton.tonal(
                            onPressed: onShop,
                            child: const Text('تهیه پر'),
                          ),
                        ],
                      ],
                    ),
                  const SizedBox(height: 10),
                  Text(
                    remainingFree > 0
                        ? '${faNumber(remainingFree)} پرسش '
                              'رایگان باقی مانده است.'
                        : 'هر پرسش جدید: یک پر · '
                              'پاسخ ناموفق: بدون هزینه',
                    style: const TextStyle(color: Colors.blueGrey, height: 1.6),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
    child: Column(
      children: [
        ExcludeSemantics(
          child: Icon(icon, size: 46, color: Colors.blueGrey.shade300),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.bold, color: navy),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.blueGrey, height: 1.7),
        ),
      ],
    ),
  );
}

class LoadingPage extends StatelessWidget {
  const LoadingPage({
    super.key,
    this.message = 'در حال آماده‌سازی اطلاعات روی گوشی…',
  });

  final String message;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              Semantics(
                liveRegion: true,
                child: Text(message, textAlign: TextAlign.center),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Brand mark for Simorgh: a rising, guiding bird inspired by the Shahnameh.
class SimorghMark extends StatelessWidget {
  const SimorghMark({super.key, this.size = 96, this.compact = false})
    : assert(size > 0 && size < double.infinity);

  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: 'نشان سیمرغ',
    child: ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * .13),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1D4770), Color(0xFF10233F)],
          ),
          borderRadius: BorderRadius.circular(size * (compact ? .28 : .31)),
          border: Border.all(
            color: simorghGold.withValues(alpha: .55),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: navy.withValues(alpha: .18),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: CustomPaint(painter: _SimorghMarkPainter()),
      ),
    ),
  );
}

class _SimorghMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final gold = Paint()..color = simorghGold;
    final tealPaint = Paint()..color = teal;
    final cream = Paint()..color = const Color(0xFFFFE8B2);

    final leftWing = Path()
      ..moveTo(size.width * .48, size.height * .43)
      ..cubicTo(
        size.width * .26,
        size.height * .04,
        size.width * .04,
        size.height * .10,
        size.width * .08,
        size.height * .27,
      )
      ..cubicTo(
        size.width * .17,
        size.height * .23,
        size.width * .23,
        size.height * .35,
        size.width * .28,
        size.height * .42,
      )
      ..cubicTo(
        size.width * .17,
        size.height * .34,
        size.width * .11,
        size.height * .43,
        size.width * .15,
        size.height * .53,
      )
      ..cubicTo(
        size.width * .27,
        size.height * .48,
        size.width * .34,
        size.height * .54,
        size.width * .45,
        size.height * .60,
      )
      ..close();

    canvas.drawPath(leftWing, gold);

    final rightWing = Path()
      ..moveTo(size.width * .52, size.height * .43)
      ..cubicTo(
        size.width * .74,
        size.height * .04,
        size.width * .96,
        size.height * .10,
        size.width * .92,
        size.height * .27,
      )
      ..cubicTo(
        size.width * .83,
        size.height * .23,
        size.width * .77,
        size.height * .35,
        size.width * .72,
        size.height * .42,
      )
      ..cubicTo(
        size.width * .83,
        size.height * .34,
        size.width * .89,
        size.height * .43,
        size.width * .85,
        size.height * .53,
      )
      ..cubicTo(
        size.width * .73,
        size.height * .48,
        size.width * .66,
        size.height * .54,
        size.width * .55,
        size.height * .60,
      )
      ..close();

    canvas.drawPath(rightWing, tealPaint);

    final body = Path()
      ..moveTo(size.width * .48, size.height * .35)
      ..cubicTo(
        size.width * .40,
        size.height * .50,
        size.width * .43,
        size.height * .70,
        size.width * .57,
        size.height * .82,
      )
      ..cubicTo(
        size.width * .57,
        size.height * .68,
        size.width * .67,
        size.height * .57,
        size.width * .64,
        size.height * .45,
      )
      ..cubicTo(
        size.width * .61,
        size.height * .35,
        size.width * .54,
        size.height * .30,
        size.width * .48,
        size.height * .35,
      )
      ..close();

    canvas.drawPath(body, cream);

    final head = Path()
      ..moveTo(size.width * .48, size.height * .37)
      ..cubicTo(
        size.width * .42,
        size.height * .25,
        size.width * .47,
        size.height * .15,
        size.width * .58,
        size.height * .17,
      )
      ..cubicTo(
        size.width * .68,
        size.height * .19,
        size.width * .68,
        size.height * .29,
        size.width * .60,
        size.height * .35,
      )
      ..lineTo(size.width * .55, size.height * .43)
      ..close();

    canvas.drawPath(head, gold);

    final beak = Path()
      ..moveTo(size.width * .65, size.height * .22)
      ..lineTo(size.width * .79, size.height * .26)
      ..lineTo(size.width * .65, size.height * .30)
      ..close();

    canvas.drawPath(beak, tealPaint);

    canvas.drawCircle(
      Offset(size.width * .60, size.height * .23),
      size.width * .018,
      Paint()..color = navy,
    );
  }

  @override
  bool shouldRepaint(covariant _SimorghMarkPainter oldDelegate) => false;
}
