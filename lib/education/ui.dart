import 'package:flutter/material.dart';
import 'ai_advisor_service.dart';
import 'bazaar_billing_service.dart';
import 'education_store.dart';

const navy = Color(0xFF17324D);
const blue = Color(0xFF2867A8);
const teal = Color(0xFF217E75);
const pale = Color(0xFFF4F7FB);

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
  final scheme = ColorScheme.fromSeed(seedColor: blue, primary: blue, secondary: teal);
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
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(48, 48),
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
