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
  final scheme = ColorScheme.fromSeed(seedColor: navy, primary: navy, secondary: teal, tertiary: simorghGold);
  final base = ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: pale);
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'Vazirmatn', bodyColor: navy, displayColor: navy),
    appBarTheme: const AppBarTheme(backgroundColor: pale, foregroundColor: navy, centerTitle: true, elevation: 0),
    cardTheme: CardThemeData(color: Colors.white, elevation: 0, margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Color(0xFFE3EAF2)))),
    inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFD8E2ED))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFD8E2ED)))),
    navigationBarTheme: NavigationBarThemeData(backgroundColor: Colors.white, indicatorColor: blue.withValues(alpha: .12),
        labelTextStyle: WidgetStatePropertyAll(base.textTheme.labelSmall?.copyWith(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w600))),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(backgroundColor: teal, foregroundColor: navy, minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

class NoticeCard extends StatelessWidget {
  const NoticeCard({super.key, required this.text, this.icon = Icons.info_outline, this.warning = false});
  final String text;
  final IconData icon;
  final bool warning;
  @override
  Widget build(BuildContext context) => Card(
    color: warning ? const Color(0xFFFFF5E5) : null,
    child: Padding(padding: const EdgeInsets.all(16), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 22, color: warning ? Colors.deepOrange.shade800 : teal),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(height: 1.8))),
    ])),
  );
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
          const Icon(Icons.account_balance_wallet_outlined, color: teal, size: 30),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('اعتبار هوش مصنوعی', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('${faNumber(store.credits)} اعتبار', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          ])),
          if (onShop != null) FilledButton.tonal(onPressed: onShop, child: const Text('خرید اعتبار')),
        ]),
        const SizedBox(height: 10),
        Align(alignment: Alignment.centerRight, child: Text(
          store.freeAiUsesRemaining > 0
              ? '${faNumber(store.freeAiUsesRemaining)} پاسخ موفق رایگان باقی مانده است.'
              : 'هر پاسخ موفق: یک اعتبار · درخواست ناموفق: بدون هزینه',
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
