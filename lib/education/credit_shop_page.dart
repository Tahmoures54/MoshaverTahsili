import 'package:flutter/material.dart';
import 'education_store.dart';
import 'bazaar_billing_service.dart';

class CreditShopPage extends StatefulWidget {
  const CreditShopPage({super.key, required this.store});
  final EducationStore store;
  @override
  State<CreditShopPage> createState() => _CreditShopPageState();
}

class _CreditShopPageState extends State<CreditShopPage> {
  late final BazaarBillingService billing = BazaarBillingService(widget.store);
  String? busyProduct;
  bool restoring = false;

  static const packages = <({String id, String title, String credits, String description})>[
    (id: 'credit_10', title: 'بسته برنزی', credits: '۱۰ اعتبار', description: 'برای شروع و استفاده محدود'),
    (id: 'credit_35', title: 'بسته نقره‌ای', credits: '۲۵ اعتبار', description: 'انتخاب متعادل برای استفاده بیشتر'),
    (id: 'credit_90', title: 'بسته طلایی', credits: '۶۰ اعتبار', description: 'مناسب استفاده پرتکرار'),
  ];

  Future<void> buy(String id) async {
    if (!billing.isConfigured) { _message('کلید عمومی بازار در نسخه فعلی تنظیم نشده است.'); return; }
    setState(() => busyProduct = id);
    try {
      await billing.buy(id);
      if (mounted) { setState(() {}); _message('خرید بررسی و اعتبار به کیف پول اضافه شد.'); }
    } catch (error) {
      if (mounted) _message(error.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => busyProduct = null); }
  }

  Future<void> restore() async {
    if (!billing.isConfigured) { _message('کلید عمومی بازار در نسخه فعلی تنظیم نشده است.'); return; }
    setState(() => restoring = true);
    try {
      await billing.restorePurchases();
      if (mounted) { setState(() {}); _message('بررسی خریدهای قبلی انجام شد.'); }
    } catch (error) {
      if (mounted) _message(error.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => restoring = false); }
  }

  void _message(String value) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));

  @override
  void dispose() { billing.disconnect(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('خرید اعتبار مشاور هوشمند')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      Card(child: Padding(padding: const EdgeInsets.all(18), child: Row(children: [
        const Icon(Icons.account_balance_wallet_outlined, size: 34, color: Colors.teal),
        const SizedBox(width: 12),
        const Expanded(child: Text('اعتبار باقی‌مانده', style: TextStyle(fontWeight: FontWeight.bold))),
        Text(widget.store.credits.toString(), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
      ]))),
      const SizedBox(height: 8),
      const Card(child: Padding(padding: EdgeInsets.all(14), child: Text(
        'دو درخواست موفق نخست رایگان است. پس از آن، برای هر پاسخ موفق هوش مصنوعی یک اعتبار مصرف می‌شود. در صورت خطا یا دریافت پاسخ نامعتبر، اعتباری کسر نمی‌شود. اعتبارهای خریداری‌شده روی همین گوشی نگهداری می‌شوند.',
        style: TextStyle(height: 1.7),
      ))),
      const SizedBox(height: 14),
      ...packages.map((item) => Card(child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: const CircleAvatar(child: Icon(Icons.bolt)),
        title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('${item.credits} · ${item.description}\nقیمت نهایی در پنجره پرداخت بازار نمایش داده می‌شود.'),
        isThreeLine: true,
        trailing: FilledButton(
          onPressed: busyProduct == null ? () => buy(item.id) : null,
          child: busyProduct == item.id ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('خرید'),
        ),
      ))),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: restoring || busyProduct != null ? null : restore,
        icon: restoring ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.restore),
        label: const Text('بررسی و بازیابی خریدهای بازار'),
      ),
      if (!billing.isConfigured)
        const Padding(padding: EdgeInsets.only(top: 12), child: Text(
          'خرید در این بیلد فعال نیست؛ BAZAAR_RSA_PUBLIC_KEY باید هنگام ساخت APK تزریق شود.',
          style: TextStyle(color: Colors.deepOrange, height: 1.6),
        )),
    ]),
  );
}
