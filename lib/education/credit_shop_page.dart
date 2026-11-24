import 'dart:async';

import 'package:flutter/material.dart';

import 'bazaar_billing_service.dart';
import 'education_store.dart';
import 'ui.dart';

class CreditShopPage extends StatefulWidget {
  const CreditShopPage({
    super.key,
    required this.store,
    this.billing,
  });

  final EducationStore store;

  /// Prefer an application-scoped service for the native billing plugin.
  ///
  /// Injected services must use the same EducationStore as this page.
  final BazaarBillingService? billing;

  @override
  State<CreditShopPage> createState() => _CreditShopPageState();
}

class _CreditShopPageState extends State<CreditShopPage> {
  static const int _historyLimit = 250;

  late BazaarBillingService _billing;
  late bool _ownsBilling;

  Timer? _billingMonitor;

  String? _operation;
  String? _error;

  Map<String, String> _prices = {};

  bool _observedBillingBusy = false;
  bool _observedRecoveryRequired = false;

  int _generation = 0;

  bool get _isBusy {
    return _operation != null || _billing.isBusy;
  }

  bool get _hasWalletError {
    return widget.store.walletError != null;
  }

  bool get _canUseBilling {
    return _billing.isConfigured &&
        !_isBusy &&
        !_hasWalletError;
  }

  @override
  void initState() {
    super.initState();

    _attachBilling();
  }

  void _attachBilling() {
    final injected = widget.billing;

    if (injected != null &&
        !identical(injected.store, widget.store)) {
      throw ArgumentError(
        'CreditShopPage and its billing service must use '
        'the same EducationStore.',
      );
    }

    _ownsBilling = injected == null;
    _billing = injected ?? BazaarBillingService(widget.store);

    _observedBillingBusy = _billing.isBusy;
    _observedRecoveryRequired =
        _billing.requiresPurchaseRecovery;

    // BazaarBillingService currently exposes getters, not a Listenable.
    // Only rebuild when its observable state changes.
    _billingMonitor = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (!mounted) return;

        final busy = _billing.isBusy;
        final recovery = _billing.requiresPurchaseRecovery;

        if (busy == _observedBillingBusy &&
            recovery == _observedRecoveryRequired) {
          return;
        }

        setState(() {
          _observedBillingBusy = busy;
          _observedRecoveryRequired = recovery;
        });
      },
    );

    if (_billing.isConfigured) {
      unawaited(_loadProducts());
    }
  }

  @override
  void didUpdateWidget(covariant CreditShopPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (identical(oldWidget.store, widget.store) &&
        identical(oldWidget.billing, widget.billing)) {
      return;
    }

    // Ignore completions belonging to the previously attached service.
    _generation++;
    _billingMonitor?.cancel();

    if (_ownsBilling) {
      unawaited(_billing.disconnect());
    }

    _operation = null;
    _error = null;
    _prices = {};

    _attachBilling();
  }

  @override
  void dispose() {
    _generation++;
    _billingMonitor?.cancel();

    // Do not dispose an application-scoped injected service.
    if (_ownsBilling) {
      unawaited(_billing.disconnect());
    }

    super.dispose();
  }

  bool _isCurrent(int generation) {
    return mounted && generation == _generation;
  }

  String _errorMessage(Object value) {
    if (value is BillingException) {
      return value.message;
    }

    final message = friendlyError(value).trim();

    return message.isEmpty
        ? 'عملیات کامل نشد. دوباره تلاش کن.'
        : message;
  }

  void _finishOperation(int generation) {
    if (!_isCurrent(generation)) return;

    setState(() {
      _operation = null;
      _observedBillingBusy = _billing.isBusy;
      _observedRecoveryRequired =
          _billing.requiresPurchaseRecovery;
    });
  }

  // ---------------------------------------------------------------------------
  // Product prices
  // ---------------------------------------------------------------------------

  Future<void> _loadProducts() async {
    if (!mounted || !_canUseBilling) return;

    final generation = _generation;
    final service = _billing;

    setState(() {
      _operation = 'prices';
      _error = null;

      // Do not retain stale prices after an unsuccessful refresh.
      _prices = {};
    });

    try {
      final products = await service.loadProducts();

      if (!_isCurrent(generation)) return;

      setState(() {
        _prices = {
          for (final item in products)
            item.product.id: item.price,
        };

        if (_prices.isEmpty) {
          _error = 'در حال حاضر بسته‌ای برای خرید دریافت نشد. '
              'کمی بعد دوباره قیمت‌ها را دریافت کن.';
        }
      });
    } on Object catch (value) {
      if (!_isCurrent(generation)) return;

      setState(() {
        _error = _errorMessage(value);
      });
    } finally {
      _finishOperation(generation);
    }
  }

  // ---------------------------------------------------------------------------
  // Purchase and recovery
  // ---------------------------------------------------------------------------

  Future<void> _buy(String id) async {
    if (!_canUseBilling ||
        _billing.requiresPurchaseRecovery ||
        !_prices.containsKey(id) ||
        CreditCatalog.byId(id) == null) {
      return;
    }

    final service = _billing;

    await _run(
      id,
      () => service.buy(id),
    );
  }

  Future<void> _restore() async {
    if (!_canUseBilling) return;

    final service = _billing;

    await _run(
      'restore',
      service.restorePurchases,
    );
  }

  Future<void> _run(
    String operation,
    Future<BillingResult> Function() action,
  ) async {
    if (!mounted || !_canUseBilling) return;

    final generation = _generation;

    setState(() {
      _operation = operation;
      _error = null;
    });

    try {
      final result = await action();

      if (!_isCurrent(generation)) return;

      // Keep partial failures visible after the snackbar disappears.
      if (result.failed > 0 ||
          result.skipped > 0 ||
          result.consumptionPending) {
        setState(() {
          _error = result.message;
        });
      }

      showMessage(context, result.message);
    } on BillingException catch (value) {
      if (!_isCurrent(generation)) return;

      if (value.cancelled) {
        showMessage(context, value.message);
      } else {
        setState(() {
          _error = value.message;
        });
      }
    } on Object catch (value) {
      if (!_isCurrent(generation)) return;

      setState(() {
        _error = _errorMessage(value);
      });
    } finally {
      _finishOperation(generation);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  Widget _spinner() {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  Widget _buttonContent(
    String label, {
    required bool loading,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (loading) ...[
          _spinner(),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final busy = _isBusy;
        final recoveryRequired =
            _billing.requiresPurchaseRecovery;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: PopScope(
            canPop: !busy,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('کیسه پرهای سیمرغ'),
                automaticallyImplyLeading: !busy,
              ),
              body: SafeArea(
                top: false,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    28,
                  ),
                  children: [
                    CreditSummary(store: widget.store),

                    const NoticeCard(
                      text: 'پرهای سیمرغ برای دریافت راهنمایی '
                          'مصرف می‌شوند. شرایط هدیه آغازین، '
                          'مصرف و بازگشت پرها به قواعد '
                          'سرویس بستگی دارد. '
                          'کیف پول محلی و تاریخچه خرید از '
                          'پشتیبان تحصیلی بازیابی نمی‌شوند. '
                          'حذف داده‌های برنامه یا انتقال گوشی '
                          'ممکن است باعث از دست رفتن '
                          'اعتبار محلی شود.',
                    ),

                    if (!_billing.isConfigured) ...[
                      const SizedBox(height: 8),
                      NoticeCard(
                        text: _billing.configurationMessage,
                        warning: true,
                      ),
                    ],

                    if (_hasWalletError) ...[
                      const SizedBox(height: 8),
                      Semantics(
                        liveRegion: true,
                        child: NoticeCard(
                          text: widget.store.walletError!,
                          icon: Icons.error_outline,
                          warning: true,
                        ),
                      ),
                    ],

                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Semantics(
                        liveRegion: true,
                        child: NoticeCard(
                          text: _error!,
                          icon: Icons.error_outline,
                          warning: true,
                        ),
                      ),
                    ],

                    if (recoveryRequired) ...[
                      const SizedBox(height: 8),
                      const NoticeCard(
                        text: 'وضعیت خرید قبلی هنوز کامل '
                            'بررسی نشده است. پس از پایان '
                            'عملیات بازار، ابتدا بازیابی '
                            'خریدها را اجرا کن. تا آن زمان '
                            'خرید جدید غیرفعال است.',
                        icon: Icons.restore,
                        warning: true,
                      ),
                    ],

                    if (_billing.isBusy &&
                        _operation == null) ...[
                      const SizedBox(height: 8),
                      const NoticeCard(
                        text: 'عملیات قبلی بازار هنوز '
                            'پایان نیافته است. پایان زمان '
                            'انتظار برنامه به معنی لغو '
                            'پرداخت نیست. فعلاً پرداخت '
                            'دیگری انجام نده.',
                        icon: Icons.hourglass_top,
                        warning: true,
                      ),
                    ],

                    const SizedBox(height: 18),

                    const Text(
                      'بسته‌های پر سیمرغ',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 10),

                    for (final product in CreditCatalog.products)
                      _buildProductCard(product),

                    if (_billing.isConfigured) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed:
                            _canUseBilling ? _loadProducts : null,
                        icon: _operation == 'prices'
                            ? _spinner()
                            : const Icon(Icons.refresh),
                        label: Text(
                          _operation == 'prices'
                              ? 'در حال دریافت قیمت‌ها…'
                              : 'دریافت دوباره قیمت‌ها',
                        ),
                      ),
                    ],

                    const SizedBox(height: 8),

                    OutlinedButton.icon(
                      onPressed: _canUseBilling ? _restore : null,
                      icon: _operation == 'restore'
                          ? _spinner()
                          : const Icon(Icons.restore),
                      label: Text(
                        _operation == 'restore'
                            ? 'در حال بررسی خریدها…'
                            : 'بازیابی خریدها',
                      ),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      'اگر پرداخت انجام شده ولی برنامه '
                      'بسته شده، ابتدا بازیابی را بزن. '
                      'این گزینه خریدهای قابل دریافت از '
                      'بازار را بررسی می‌کند؛ خریدهای '
                      'مصرف‌شده قبلی ممکن است در آن '
                      'فهرست نباشند و این عملیات تضمین '
                      'بازیابی اعتبار پس از حذف برنامه نیست.',
                      style: TextStyle(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                        height: 1.7,
                      ),
                    ),

                    const SizedBox(height: 24),

                    const Text(
                      'تاریخچه پرها',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 10),

                    _buildHistory(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildProductCard(CreditProduct product) {
    final price = _prices[product.id];
    final isBuying = _operation == product.id;

    final canBuy = _canUseBilling &&
        !_billing.requiresPurchaseRecovery &&
        price != null;

    final mutedColor =
        Theme.of(context).colorScheme.onSurfaceVariant;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                const SizedBox(width: 8),
                Text(
                  '${faNumber(product.credits)} پر',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(product.description),
            const SizedBox(height: 6),
            Text(
              price == null
                  ? 'قیمت این بسته هنوز از بازار دریافت نشده است.'
                  : 'قیمت بازار: $price\n'
                      'مبلغ نهایی را پیش از تأیید در بازار بررسی کن.',
              style: TextStyle(
                color: mutedColor,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: canBuy
                    ? () => unawaited(_buy(product.id))
                    : null,
                child: _buttonContent(
                  isBuying
                      ? 'در حال بررسی خرید…'
                      : 'خرید از بازار',
                  loading: isBuying,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistory() {
    // Preserve the ordering defined by EducationStore.
    final history = widget.store.creditHistory
        .take(_historyLimit)
        .toList(growable: false);

    if (history.isEmpty) {
      return const EmptyState(
        title: 'هنوز تراکنشی ثبت نشده',
        subtitle: 'دریافت، مصرف و بازگشت پرهای سیمرغ '
            'اینجا نمایش داده می‌شوند.',
        icon: Icons.receipt_long_outlined,
      );
    }

    return Column(
      children: [
        for (final item in history)
          _buildHistoryItem(item),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'نمایش حداکثر '
            '${faNumber(_historyLimit)} تراکنش '
            'با ترتیب ذخیره‌سازی برنامه. '
            'حذف یا محدودکردن تاریخچه نمایشی نباید '
            'دفتر توکن‌های خرید را حذف کند.',
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant,
              height: 1.7,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> item) {
    final kind = item['kind']?.toString() ?? '';
    final status = item['status']?.toString() ?? '';

    final rawTitle = item['title']?.toString().trim() ?? '';
    final title = rawTitle.isEmpty
        ? 'تراکنش پر سیمرغ'
        : rawTitle;

    final value = item['amount'];
    final parsed = value is num
        ? value
        : num.tryParse(value?.toString() ?? '');

    final validAmount = parsed != null && parsed.isFinite;
    final amount = validAmount ? parsed.abs() : 0;

    final isAi = kind == 'ai';
    final isAddition =
        kind == 'purchase' || kind == 'bonus';
    final isRefund = kind == 'refund';

    final IconData icon;
    final String amountText;

    if (!validAmount) {
      icon = Icons.receipt_long_outlined;
      amountText = 'نامشخص';
    } else if (isAi) {
      icon = Icons.auto_awesome;
      amountText = amount == 0
          ? 'رایگان'
          : '−${faNumber(amount)} پر';
    } else if (isAddition || isRefund) {
      icon = isRefund
          ? Icons.undo
          : Icons.add_circle_outline;

      amountText = '+${faNumber(amount)} پر';
    } else {
      // Unknown transaction kinds must not be assumed to add credit.
      icon = Icons.receipt_long_outlined;
      amountText = '${faNumber(parsed)} پر';
    }

    return Card(
      child: ListTile(
        leading: Icon(
          icon,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(title),
        subtitle: Text(
          '${_date(item['createdAt']?.toString() ?? '')}'
          '${_status(status)}',
        ),
        trailing: Text(
          amountText,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  String _date(String raw) {
    final date = DateTime.tryParse(raw)?.toLocal();

    if (date == null) return 'زمان ثبت نشده';

    String two(int value) {
      return value.toString().padLeft(2, '0');
    }

    return 'میلادی: ${faNumber(
      '${date.year}/${two(date.month)}/${two(date.day)} '
      '${two(date.hour)}:${two(date.minute)}',
    )}';
  }

  String _status(String status) {
    return switch (status) {
      'pending' => ' · در حال پردازش',
      'refunded' => ' · پر برگشت خورد',
      'failed' => ' · ناموفق',
      'cancelled' => ' · لغوشده',
      'completed' || 'success' || 'credited' =>
        ' · ثبت‌شده',
      '' => '',
      _ => ' · وضعیت نامشخص',
    };
  }
}
