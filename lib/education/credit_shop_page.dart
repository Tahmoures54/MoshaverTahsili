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
  late final BazaarBillingService billing;
  late final bool _ownsBilling;

  String? operation;
  String? error;

  Map<String, String> prices = {};

  bool _disposed = false;

  @override
  void initState() {
    super.initState();

    _ownsBilling = widget.billing == null;
    billing = widget.billing ?? BazaarBillingService(widget.store);

    if (billing.isConfigured) {
      unawaited(loadProducts());
    }
  }

  bool get _isBusy => operation != null;

  Future<void> loadProducts() async {
    if (_isBusy || !billing.isConfigured || _disposed) {
      return;
    }

    setState(() {
      operation = 'prices';
      error = null;
    });

    try {
      final products = await billing.loadProducts();

      if (!mounted || _disposed) return;

      setState(() {
        prices = {for (final item in products) item.product.id: item.price};
      });

      if (products.isEmpty) {
        setState(() {
          error =
              'در حال حاضر بسته‌ای برای خرید دریافت نشد. '
              'لطفاً کمی بعد دوباره تلاش کنید.';
        });
      }
    } on Object catch (value) {
      if (!mounted || _disposed) return;

      setState(() {
        error = friendlyError(value);
      });
    } finally {
      if (mounted && !_disposed) {
        setState(() {
          operation = null;
        });
      }
    }
  }

  Future<void> buy(String id) {
    return _run(id, () => billing.buy(id));
  }

  Future<void> restore() {
    return _run('restore', billing.restorePurchases);
  }

  Future<void> _run(String id, Future<BillingResult> Function() action) async {
    if (_isBusy || _disposed) return;

    setState(() {
      operation = id;
      error = null;
    });

    try {
      final result = await action();

      if (!mounted || _disposed) return;

      showMessage(context, result.message);
    } on Object catch (value) {
      if (!mounted || _disposed) return;

      setState(() {
        error = friendlyError(value);
      });
    } finally {
      if (mounted && !_disposed) {
        setState(() {
          operation = null;
        });
      }
    }
  }

  Widget _spinner() {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  @override
  void dispose() {
    _disposed = true;

    // فقط سرویسی را قطع می‌کنیم که خود این صفحه ساخته است.
    // سرویس تزریق‌شده ممکن است در بخش دیگری از برنامه استفاده شود.
    if (_ownsBilling) {
      unawaited(billing.disconnect());
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('کیسه پرهای سیمرغ')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          CreditSummary(store: widget.store),

          const NoticeCard(
            text:
                'برای شروع، ۵ پر هدیه سیمرغ دریافت می‌کنی. '
                'هر پرسش تازه‌ای که برای دریافت راهنمایی از سیمرغ می‌فرستی، '
                'یک پر مصرف می‌کند؛ اگر پاسخ معتبر دریافت نشود، '
                'پر رزروشده به کیسه‌ات برمی‌گردد. '
                'پرها روی همین گوشی نگهداری می‌شوند؛ '
                'حذف برنامه یا انتقال گوشی می‌تواند باعث از دست رفتن آن‌ها شود.',
          ),

          if (!billing.isConfigured)
            NoticeCard(text: billing.configurationMessage, warning: true),

          if (error != null)
            NoticeCard(text: error!, icon: Icons.error_outline, warning: true),

          const SizedBox(height: 10),

          const Text(
            'بسته‌های پر سیمرغ',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 10),

          for (final product in CreditCatalog.products)
            _buildProductCard(product),

          if (billing.isConfigured && operation == 'prices')
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            ),

          if (billing.isConfigured && operation == null && prices.isEmpty)
            OutlinedButton.icon(
              onPressed: loadProducts,
              icon: const Icon(Icons.refresh),
              label: const Text('تلاش برای دریافت قیمت‌ها'),
            ),

          const SizedBox(height: 8),

          OutlinedButton.icon(
            onPressed: !billing.isConfigured || _isBusy ? null : restore,
            icon: operation == 'restore'
                ? _spinner()
                : const Icon(Icons.restore),
            label: const Text('بازیابی خریدها'),
          ),

          const SizedBox(height: 8),

          const Text(
            'اگر پرداخت انجام شده ولی برنامه بسته شده، '
            'ابتدا بازیابی را بزن. خریدهای مصرف‌شده قبلی ممکن است '
            'در فهرست قابل بازیابی بازار نباشند.',
            style: TextStyle(color: Colors.blueGrey, height: 1.7),
          ),

          const SizedBox(height: 24),

          const Text(
            'تاریخچه پرها',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 10),

          ListenableBuilder(
            listenable: widget.store,
            builder: (context, _) {
              final history = widget.store.creditHistory;

              if (history.isEmpty) {
                return const EmptyState(
                  title: 'هنوز تراکنشی ثبت نشده',
                  subtitle:
                      'دریافت، فراخوان و بازگشت پرهای سیمرغ '
                      'اینجا نمایش داده می‌شوند.',
                  icon: Icons.receipt_long_outlined,
                );
              }

              return Column(
                children: [
                  for (final item in history) _buildHistoryItem(item),

                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'نمایش حداکثر ۲۵۰ تراکنش اخیر؛ '
                      'شناسه خریدهای ثبت‌شده برای جلوگیری از شارژ '
                      'تکراری نگهداری می‌شود.',
                      style: TextStyle(color: Colors.blueGrey, height: 1.7),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(CreditProduct product) {
    final price = prices[product.id];
    final isBuying = operation == product.id;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SimorghFeatherMark(size: 23),
                const SizedBox(width: 8),

                Expanded(
                  child: Text(
                    product.title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                Text(
                  '${faNumber(product.feathers)} پر',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),

            const SizedBox(height: 8),

            Text(product.description),

            const SizedBox(height: 6),

            Text(
              price ?? 'قیمت نهایی هنگام پرداخت در بازار نمایش داده می‌شود.',
              style: const TextStyle(color: Colors.blueGrey, height: 1.6),
            ),

            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: !billing.isConfigured || _isBusy || price == null
                    ? null
                    : () => buy(product.id),
                child: isBuying ? _spinner() : const Text('خرید از بازار'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> item) {
    final kind = item['kind']?.toString() ?? '';
    final status = item['status']?.toString() ?? '';
    final title = item['title']?.toString() ?? 'تراکنش پر سیمرغ';

    final amountValue = item['amount'];
    final amount = amountValue is num
        ? amountValue
        : num.tryParse(amountValue?.toString() ?? '') ?? 0;

    final isAi = kind == 'ai';
    final isAddition = kind == 'purchase' || kind == 'bonus';
    final isRefund = kind == 'refund';

    final icon = isAddition
        ? Icons.add_circle_outline
        : isRefund
        ? Icons.undo
        : Icons.auto_awesome;

    final iconColor = isAi ? blue : teal;

    final amountText = isAi && amount == 0
        ? 'رایگان'
        : '${isAi ? '−' : '+'}${faNumber(amount)} پر';

    return Card(
      child: ListTile(
        leading: Icon(icon, color: iconColor),
        title: Text(title),
        subtitle: Text(
          _date(item['createdAt']?.toString() ?? '') + _status(status),
        ),
        trailing: Text(
          amountText,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  String _date(String raw) {
    final date = DateTime.tryParse(raw)?.toLocal();

    if (date == null) {
      return 'زمان ثبت نشده';
    }

    String two(int value) {
      return value.toString().padLeft(2, '0');
    }

    // اینجا تاریخ میلادی نمایش داده می‌شود.
    // برای تبدیل دقیق به شمسی باید از مبدل تاریخ موجود در پروژه استفاده شود.
    return faNumber(
      '${date.year}/${two(date.month)}/${two(date.day)} '
      '${two(date.hour)}:${two(date.minute)}',
    );
  }

  String _status(String status) {
    return switch (status) {
      'pending' => ' · در حال پردازش',
      'refunded' => ' · پر برگشت خورد',
      _ => ' · ثبت‌شده',
    };
  }
}
