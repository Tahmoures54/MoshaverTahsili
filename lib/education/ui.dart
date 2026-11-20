import 'package:flutter/material.dart';
import 'ai_advisor_service.dart';
import 'bazaar_billing_service.dart';
import 'education_store.dart';

const navy = Color(0xFF142D4E);
const blue = Color(0xFF236B9A);
const teal = Color(0xFF20B8AE);
const pale = Color(0xFFF5F8FC);
const simorghGold = Color(0xFFF2BE58);

String faNumber(Object? value) {
  var text = value?.toString() ?? '';
  for (var i = 0; i < 10; i++) {
    text = text.replaceAll(i.toString(), '۰۱۲۳۴۵۶۷۸۹'[i]);
  }
  return text;
}

String digitsToEnglish(String value) {
  var result = value;
  for (var i = 0; i < 10; i++) {
    result = result.replaceAll('۰۱۲۳۴۵۶۷۸۹'[i], i.toString())
        .replaceAll('٠١٢٣٤٥٦٧٨٩'[i], i.toString());
  }
  return result.replaceAll('٫', '.').replaceAll('٬', '').replaceAll(',', '.').trim();
}

String friendlyError(Object error) {
  if (error is AiException || error is LocalDataException || error is BillingException) {
    return error.toString();
  }
  return 'این عملیات کامل نشد. فضای خالی گوشی و اتصال اینترنت را بررسی کن و دوباره تلاش کن.';
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
    colorScheme: scheme,
    scaffoldBackgroundColor: pale,
    visualDensity: VisualDensity.standard,
  );
  final textTheme = base.textTheme.apply(
    fontFamily: 'Vazirmatn',
    bodyColor: navy,
    displayColor: navy,
  ).copyWith(
    headlineSmall: base.textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.w800, height: 1.45,
    ),
    titleLarge: base.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w800, height: 1.45,
    ),
    titleMedium: base.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700, height: 1.5,
    ),
    bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.8),
    bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.75),
    labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
  );
  return base.copyWith(
    textTheme: textTheme,
    appBarTheme: const AppBarTheme(
      backgroundColor: pale,
      foregroundColor: navy,
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 1,
      titleTextStyle: TextStyle(
        fontFamily: 'Vazirmatn', color: navy, fontSize: 18,
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
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      elevation: 0,
      indicatorColor: teal.withValues(alpha: .16),
      labelTextStyle: WidgetStatePropertyAll(
        textTheme.labelSmall?.copyWith(
          fontFamily: 'Vazirmatn', fontWeight: FontWeight.w700,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: teal,
        foregroundColor: navy,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        textStyle: const TextStyle(
          fontFamily: 'Vazirmatn', fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: navy,
        minimumSize: const Size(44, 44),
        side: const BorderSide(color: Color(0xFFD5E0EA)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      showCloseIcon: true,
    ),
    dividerTheme: const DividerThemeData(
      color: Color(0xFFE5EBF1), thickness: 1, space: 1,
    ),
  );
}

/// Shared brand components. Keep the mascot expressive but let learning content
/// remain the visual priority on small screens.
class SimorghHomeHero extends StatelessWidget {
  const SimorghHomeHero({
    super.key, required this.nickname, required this.gradeLine,
    required this.onChat,
  });

  final String nickname;
  final String gradeLine;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    final greeting = nickname.isEmpty ? 'درود بر جوینده دانایی!' : 'درود، $nickname!';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF1D4770), Color(0xFF142D4E), Color(0xFF10233F)],
        ),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: simorghGold.withValues(alpha: .42)),
        boxShadow: [
          BoxShadow(color: navy.withValues(alpha: .12), blurRadius: 18,
            offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SimorghMark(size: 82, compact: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(greeting, style: const TextStyle(
                      color: Color(0xFFFFE8B2), fontSize: 19,
                      fontWeight: FontWeight.w900, height: 1.5,
                    )),
                    const SizedBox(height: 5),
                    const Text('همراه دانای راه آینده', style: TextStyle(
                      color: Colors.white, fontSize: 13,
                      fontWeight: FontWeight.w700,
                    )),
                    if (gradeLine.trim().isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(gradeLine, maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFD9E7F2), fontSize: 11, height: 1.6,
                        )),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'من مسیر را روشن‌تر می‌کنم؛ پرواز را خودت انجام می‌دهی. '
            'امروز با یک قدم کوچک شروع کنیم.',
            style: TextStyle(color: Colors.white, height: 1.8, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
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
  }
}

class SimorghSectionTitle extends StatelessWidget {
  const SimorghSectionTitle({super.key, required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            width: 4, height: 22,
            decoration: BoxDecoration(
              color: teal, borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(color: navy, fontWeight: FontWeight.w800))),
        ]),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 13),
            child: Text(subtitle!, style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: const Color(0xFF617387), height: 1.6)),
          ),
        ],
      ],
    ),
  );
}

class NoticeCard extends StatelessWidget {
  const NoticeCard({super.key, required this.text, this.icon = Icons.info_outline, this.warning = false});
  final String text;
  final IconData icon;
  final bool warning;
  @override
  Widget build(BuildContext context) {
    final background = warning ? const Color(0xFFFFF5E5) : const Color(0xFFEAF6F4);
    final foreground = warning ? const Color(0xFF8A4B12) : navy;
    return Card(
      color: background,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 21,
            color: warning ? const Color(0xFFB65D19) : teal),
          const SizedBox(width: 11),
          Expanded(child: Text(text, style: TextStyle(
            color: foreground, height: 1.8, fontSize: 13,
          ))),
        ]),
      ),
    );
  }
}

class SimorghFeatherMark extends StatelessWidget {
  const SimorghFeatherMark({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size * 1.15,
    child: CustomPaint(painter: _SimorghFeatherPainter()),
  );
}

class _SimorghFeatherPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final feather = Path()
      ..moveTo(size.width * .15, size.height * .88)
      ..cubicTo(size.width * .12, size.height * .55, size.width * .30,
          size.height * .16, size.width * .84, size.height * .08)
      ..cubicTo(size.width * .82, size.height * .49, size.width * .61,
          size.height * .79, size.width * .15, size.height * .88)
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
      canvas.drawLine(Offset(x, y), Offset(x - size.width * .13,
          y + size.height * .035), shaft);
      canvas.drawLine(Offset(x, y), Offset(x + size.width * .08,
          y + size.height * .025), shaft);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CreditSummary extends StatelessWidget {
  const CreditSummary({super.key, required this.store, this.onShop});
  final EducationStore store;
  final VoidCallback? onShop;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) {
      if (store.walletError != null) return NoticeCard(text: store.walletError!, warning: true);
      return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
        Row(children: [
          const SimorghFeatherMark(size: 28),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('پرهای سیمرغ', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('${faNumber(store.feathers)} پر', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ])),
          if (onShop != null) FilledButton.tonal(onPressed: onShop, child: const Text('تهیه پر')),
        ]),
        const SizedBox(height: 10),
        Align(alignment: Alignment.centerRight, child: Text(
          store.freeAiUsesRemaining > 0
              ? '${faNumber(store.freeAiUsesRemaining)} پرسش رایگان باقی مانده است.'
              : 'هر پرسش جدید: یک پر · پاسخ ناموفق: بدون هزینه',
          style: const TextStyle(color: Colors.blueGrey, height: 1.6),
        )),
      ])));
    },
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.subtitle, required this.icon});
  final String title, subtitle;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
    child: Column(children: [
      Icon(icon, size: 46, color: Colors.blueGrey.shade300),
      const SizedBox(height: 12),
      Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, color: navy)),
      const SizedBox(height: 6),
      Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.blueGrey, height: 1.7)),
    ]));
}

class LoadingPage extends StatelessWidget {
  const LoadingPage({super.key, this.message = 'در حال آماده‌سازی اطلاعات روی گوشی…'});
  final String message;
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    const CircularProgressIndicator(), const SizedBox(height: 20), Text(message),
  ])));
}


/// Brand mark for Simorgh: a rising, guiding bird inspired by the Shahnameh.
class SimorghMark extends StatelessWidget {
  const SimorghMark({super.key, this.size = 96, this.compact = false});
  final double size;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
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
      border: Border.all(color: simorghGold.withValues(alpha: .55), width: 1),
      boxShadow: [BoxShadow(color: navy.withValues(alpha: .18), blurRadius: 18, offset: const Offset(0, 7))],
    ),
    child: CustomPaint(painter: _SimorghMarkPainter()),
  );
}

class _SimorghMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gold = Paint()..color = simorghGold..style = PaintingStyle.fill;
    final tealPaint = Paint()..color = teal..style = PaintingStyle.fill;
    final cream = Paint()..color = const Color(0xFFFFE8B2)..style = PaintingStyle.fill;

    final leftWing = Path()
      ..moveTo(size.width * .48, size.height * .43)
      ..cubicTo(size.width * .26, size.height * .04, size.width * .04, size.height * .10, size.width * .08, size.height * .27)
      ..cubicTo(size.width * .17, size.height * .23, size.width * .23, size.height * .35, size.width * .28, size.height * .42)
      ..cubicTo(size.width * .17, size.height * .34, size.width * .11, size.height * .43, size.width * .15, size.height * .53)
      ..cubicTo(size.width * .27, size.height * .48, size.width * .34, size.height * .54, size.width * .45, size.height * .60)
      ..close();
    canvas.drawPath(leftWing, gold);

    final rightWing = Path()
      ..moveTo(size.width * .52, size.height * .43)
      ..cubicTo(size.width * .74, size.height * .04, size.width * .96, size.height * .10, size.width * .92, size.height * .27)
      ..cubicTo(size.width * .83, size.height * .23, size.width * .77, size.height * .35, size.width * .72, size.height * .42)
      ..cubicTo(size.width * .83, size.height * .34, size.width * .89, size.height * .43, size.width * .85, size.height * .53)
      ..cubicTo(size.width * .73, size.height * .48, size.width * .66, size.height * .54, size.width * .55, size.height * .60)
      ..close();
    canvas.drawPath(rightWing, tealPaint);

    final body = Path()
      ..moveTo(size.width * .48, size.height * .35)
      ..cubicTo(size.width * .40, size.height * .50, size.width * .43, size.height * .70, size.width * .57, size.height * .82)
      ..cubicTo(size.width * .57, size.height * .68, size.width * .67, size.height * .57, size.width * .64, size.height * .45)
      ..cubicTo(size.width * .61, size.height * .35, size.width * .54, size.height * .30, size.width * .48, size.height * .35)
      ..close();
    canvas.drawPath(body, cream);

    final head = Path()
      ..moveTo(size.width * .48, size.height * .37)
      ..cubicTo(size.width * .42, size.height * .25, size.width * .47, size.height * .15, size.width * .58, size.height * .17)
      ..cubicTo(size.width * .68, size.height * .19, size.width * .68, size.height * .29, size.width * .60, size.height * .35)
      ..lineTo(size.width * .55, size.height * .43)
      ..close();
    canvas.drawPath(head, gold);
    final beak = Path()
      ..moveTo(size.width * .65, size.height * .22)
      ..lineTo(size.width * .79, size.height * .26)
      ..lineTo(size.width * .65, size.height * .30)
      ..close();
    canvas.drawPath(beak, tealPaint);
    canvas.drawCircle(Offset(size.width * .60, size.height * .23), size.width * .018, Paint()..color = navy);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
