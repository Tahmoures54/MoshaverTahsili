import 'dart:async';

import 'package:flutter/material.dart';
import 'bazaar_billing_service.dart';
import 'education_store.dart';
import 'ui.dart';

class CreditShopPage extends StatefulWidget {
  const CreditShopPage({super.key, required this.store, this.billing});
  final EducationStore store;
  final BazaarBillingService? billing;
  @override
  State<CreditShopPage> createState() => _CreditShopPageState();
}

class _CreditShopPageState extends State<CreditShopPage> {
  late final BazaarBillingService billing = widget.billing ?? BazaarBillingService(widget.store);
  String? operation;
  String? error;
  Map<String, String> prices = {};

  @override
  void initState() {
    super.initState();
    if (billing.isConfigured) unawaited(loadProducts());
  }

  Future<void> loadProducts() async {
    if (operation != null || !billing.isConfigured) return;
    setState(() { operation = 'prices'; error = null; });
    try {
      final products = await billing.loadProducts();
      if (mounted) setState(() => prices = {for (final item in products) item.product.id: item.price});
    } on Object catch (value) {
      if (mounted) setState(() => error = friendlyError(value));
    } finally {
      if (mounted) setState(() => operation = null);
    }
  }

  Future<void> buy(String id) => _run(id, () => billing.buy(id));
  Future<void> restore() => _run('restore', billing.restorePurchases);

  Future<void> _run(String id, Future<BillingResult> Function() action) async {
    if (operation != null) return;
    setState(() { operation = id; error = null; });
    try {
      final result = await action();
      if (mounted) showMessage(context, result.message);
    } on Object catch (value) {
      if (mounted) setState(() => error = friendlyError(value));
    } finally {
      if (mounted) setState(() => operation = null);
    }
  }

  Widget _spinner() => const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));

  @override
  void dispose() { unawaited(billing.disconnect()); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('کیف اعتبار و خرید')),
    body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 28), children: [
      CreditSummary(store: widget.store),
      const NoticeCard(text: 'دو پاسخ موفق نخست رایگان است. پس از آن هر پاسخ موفق یک اعتبار مصرف می‌کند. '
          'هنگام پردازش، یک اعتبار موقتاً رزرو می‌شود و در صورت خطا برمی‌گردد. '
          'اطلاعات کیف پول فقط روی همین گوشی است؛ حذف برنامه یا انتقال گوشی می‌تواند اعتبار را از بین ببرد.'),
      if (!billing.isConfigured) NoticeCard(text: billing.configurationMessage, warning: true),
      if (error != null) NoticeCard(text: error!, icon: Icons.error_outline, warning: true),
      const SizedBox(height: 10),
      const Text('بسته‌های اعتبار', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      for (final product in CreditCatalog.products) Card(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.bolt, color: teal), const SizedBox(width: 8),
            Expanded(child: Text(product.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold))),
            Text('${faNumber(product.credits)} اعتبار', style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 8),
          Text(product.description),
          const SizedBox(height: 6),
          Text(prices[product.id] ?? 'قیمت نهایی هنگام پرداخت در بازار نمایش داده می‌شود.',
              style: const TextStyle(color: Colors.blueGrey, height: 1.6)),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: FilledButton(
            onPressed: !billing.isConfigured || operation != null || prices[product.id] == null ? null : () => buy(product.id),
            child: operation == product.id ? _spinner() : const Text('خرید از بازار'),
          )),
        ]),
      )),
      if (billing.isConfigured && operation == 'prices')
        const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
      if (billing.isConfigured && operation == null && prices.isEmpty)
        OutlinedButton.icon(onPressed: loadProducts, icon: const Icon(Icons.refresh), label: const Text('تلاش برای دریافت قیمت‌ها')),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: !billing.isConfigured || operation != null ? null : restore,
        icon: operation == 'restore' ? _spinner() : const Icon(Icons.restore),
        label: const Text('بازیابی خریدها'),
      ),
      const SizedBox(height: 8),
      const Text('اگر پرداخت انجام شده ولی برنامه بسته شده، ابتدا بازیابی را بزن. خریدهای مصرف‌شده قبلی ممکن است در فهرست قابل بازیابی بازار نباشند.',
          style: TextStyle(color: Colors.blueGrey, height: 1.7)),
      const SizedBox(height: 24),
      const Text('تاریخچه اعتبار', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      ListenableBuilder(listenable: widget.store, builder: (context, _) {
        final history = widget.store.creditHistory;
        if (history.isEmpty) return const EmptyState(title: 'هنوز تراکنشی ثبت نشده', subtitle: 'خریدها و مصرف اعتبار پاسخ‌های موفق اینجا نمایش داده می‌شوند.', icon: Icons.receipt_long_outlined);
        return Column(children: [
          for (final item in history) Card(child: ListTile(
            leading: Icon(item['kind'] == 'purchase' ? Icons.add_circle_outline : item['kind'] == 'refund' ? Icons.undo : Icons.auto_awesome,
                color: item['kind'] == 'ai' ? blue : teal),
            title: Text(item['title'].toString()),
            subtitle: Text(_date(item['createdAt'].toString()) + _status(item['status'].toString())),
            trailing: Text(item['kind'] == 'ai' && item['amount'] == 0
                ? 'رایگان'
                : '${item['kind'] == 'ai' ? '−' : '+'}${faNumber(item['amount'])}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          )),
          const Text('نمایش حداکثر ۲۵۰ تراکنش اخیر؛ شناسه خریدهای ثبت‌شده برای جلوگیری از شارژ تکراری نگهداری می‌شود.',
              style: TextStyle(color: Colors.blueGrey, height: 1.7)),
        ]);
      }),
    ]),
  );

  String _date(String raw) {
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return 'زمان ثبت نشده';
    String two(int value) => value.toString().padLeft(2, '0');
    return faNumber('${date.year}/${two(date.month)}/${two(date.day)} ${two(date.hour)}:${two(date.minute)}');
  }
  String _status(String status) => switch (status) {
    'pending' => ' · در حال پردازش',
    'refunded' => ' · اعتبار برگشت خورد',
    _ => ' · ثبت‌شده',
  };
}
