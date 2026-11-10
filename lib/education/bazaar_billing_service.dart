import 'dart:async';

import 'package:cafebazaar_billing/cafebazaar_billing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'education_store.dart';

class BillingException implements Exception {
  const BillingException(this.message, {this.cancelled = false});
  final String message;
  final bool cancelled;
  @override
  String toString() => message;
}

class VerifiedPurchase {
  const VerifiedPurchase({required this.productId, required this.purchaseToken,
    required this.packageName, required this.signature, required this.purchased});
  final String productId, purchaseToken, packageName, signature;
  final bool purchased;
}

class ShopProduct {
  const ShopProduct(this.product, this.price);
  final CreditProduct product;
  final String price;
}

class BillingResult {
  const BillingResult({this.credited = 0, this.alreadyCredited = 0,
    this.consumptionPending = false, this.skipped = 0});
  final int credited, alreadyCredited, skipped;
  final bool consumptionPending;
  String get message {
    if (consumptionPending) {
      return 'اعتبارهای تأییدشده اضافه شد، اما نهایی‌سازی خرید در بازار کامل نشد. بعداً «بازیابی خریدها» را بزن.';
    }
    if (credited > 0) return '$credited بسته به کیف پول اضافه شد. خریدهای تکراری دوباره شارژ نمی‌شوند.';
    if (alreadyCredited > 0) return 'این خریدها قبلاً ثبت شده‌اند؛ اعتبار تکراری اضافه نشد.';
    if (skipped > 0) return 'خرید قابل تأییدی برای این برنامه پیدا نشد. اعتباری اضافه نشد.';
    return 'خرید مصرف‌نشده‌ای برای بازیابی پیدا نشد.';
  }
}

/// Testable boundary around the plugin. The real adapter ONLY returns purchases
/// accepted by Poolakey's enabled RSA security check; it never disables it.
abstract class BazaarGateway {
  Future<void> connect(String publicKey, {required VoidCallback onDisconnected});
  Future<VerifiedPurchase> purchase(String productId);
  Future<List<VerifiedPurchase>> purchasedProducts();
  Future<List<ShopProduct>> products(List<String> ids);
  Future<bool> consume(String token);
  Future<void> disconnect();
}

class PluginBazaarGateway implements BazaarGateway {
  @override
  Future<void> connect(String publicKey, {required VoidCallback onDisconnected}) async {
    final connected = Completer<void>();
    void succeed() { if (!connected.isCompleted) connected.complete(); }
    void fail() {
      if (!connected.isCompleted) {
        connected.completeError(const BillingException('اتصال به بازار برقرار نشد. بازار را به‌روز کن و دوباره تلاش کن.'));
      }
    }
    await Future.wait<void>([
      CafeBazaarBilling.connect(publicKey, onSucceed: succeed, onFailed: fail,
          onDisconnected: () { fail(); onDisconnected(); }),
      connected.future,
    ]).timeout(const Duration(seconds: 20), onTimeout: () {
      throw const BillingException('بازار به‌موقع پاسخ نداد. اتصال اینترنت و نصب بازار را بررسی کن.');
    });
  }

  VerifiedPurchase _map(PurchaseInfo info) => VerifiedPurchase(
    productId: info.productId, purchaseToken: info.purchaseToken,
    packageName: info.packageName, signature: info.dataSignature,
    purchased: info.purchaseState == PurchaseState.PURCHASED);

  @override
  Future<VerifiedPurchase> purchase(String productId) async => _map(await CafeBazaarBilling.purchase(productId));
  @override
  Future<List<VerifiedPurchase>> purchasedProducts() async =>
      (await CafeBazaarBilling.getAllPurchasedProducts()).map(_map).toList();
  @override
  Future<List<ShopProduct>> products(List<String> ids) async {
    final details = await CafeBazaarBilling.getInAppSkuDetails(ids);
    return [for (final item in details)
      if (CreditCatalog.byId(item.sku) != null && item.type == 'inapp' && item.price.isNotEmpty)
        ShopProduct(CreditCatalog.byId(item.sku)!, item.price)];
  }
  @override
  Future<bool> consume(String token) => CafeBazaarBilling.consume(token);
  @override
  Future<void> disconnect() => CafeBazaarBilling.disconnect();
}

class BazaarBillingService {
  BazaarBillingService(this.store, {BazaarGateway? gateway, String? publicKey,
    bool? catalogConfirmed, bool? supportedPlatform,
    this.operationTimeout = const Duration(seconds: 30)})
      : gateway = gateway ?? PluginBazaarGateway(),
        publicKey = (publicKey ?? const String.fromEnvironment('BAZAAR_RSA_PUBLIC_KEY')).trim(),
        catalogConfirmed = catalogConfirmed ?? const bool.fromEnvironment('BAZAAR_CATALOG_CONFIRMED'),
        supportedPlatform = supportedPlatform ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  final EducationStore store;
  final BazaarGateway gateway;
  final String publicKey;
  final bool catalogConfirmed, supportedPlatform;
  final Duration operationTimeout;
  static const packageName = 'ir.moshaver.tahsili';
  bool _connected = false, _busy = false, _disposed = false;
  Future<void>? _connecting;
  bool get isBusy => _busy;
  bool get isConfigured => publicKey.isNotEmpty && catalogConfirmed && supportedPlatform;
  String get configurationMessage {
    if (!supportedPlatform) return 'خرید درون‌برنامه‌ای فقط در نسخه اندروید و از طریق بازار در دسترس است.';
    if (publicKey.isEmpty) return 'کلید عمومی بازار در این نسخه تنظیم نشده است؛ خرید فعال نیست.';
    if (!catalogConfirmed) return 'شناسه محصولات هنوز با پروژه مرجع و پنل بازار تأیید نشده‌اند؛ پرداخت غیرفعال است.';
    return '';
  }

  Future<void> _connect() async {
    if (!isConfigured) throw BillingException(configurationMessage);
    if (_connected) return;
    final active = _connecting;
    if (active != null) return active;
    final future = () async {
      await gateway.connect(publicKey, onDisconnected: () => _connected = false);
      _connected = true;
    }();
    _connecting = future;
    try { await future; } finally { _connecting = null; }
  }

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    if (_disposed) throw const BillingException('صفحه خرید بسته شده است.');
    if (_busy) throw const BillingException('یک عملیات پرداخت در حال انجام است. کمی صبر کن.');
    if (store.walletError != null) throw LocalDataException(store.walletError!);
    _busy = true;
    try { return await action(); } finally {
      _busy = false;
      if (_disposed) unawaited(disconnect());
    }
  }

  Future<List<ShopProduct>> loadProducts() => _exclusive(() async {
    await _safe(_connect);
    return _safe(() => gateway.products(CreditCatalog.products.map((p) => p.id).toList())
        .timeout(operationTimeout));
  });

  void _validate(VerifiedPurchase purchase, String expectedProduct) {
    if (!purchase.purchased || purchase.productId != expectedProduct ||
        purchase.packageName != packageName || purchase.purchaseToken.trim().isEmpty ||
        purchase.purchaseToken.length > 512 || purchase.signature.trim().isEmpty) {
      throw const BillingException('خرید برای این برنامه قابل تأیید نیست؛ اعتباری اضافه نشد. با بازیابی خریدها دوباره بررسی کن.');
    }
  }

  Future<({bool credited, bool consumed})> _creditAndConsume(VerifiedPurchase purchase, String productId) async {
    final product = CreditCatalog.byId(productId)!;
    _validate(purchase, productId);
    // Persist the unique token and balance BEFORE consuming. A crash or consume
    // failure leaves a recoverable purchase, rather than an uncredited payment.
    final credited = await store.grantProduct(productId: productId,
        purchaseToken: purchase.purchaseToken, creditsToAdd: product.credits);
    try {
      final consumed = await gateway.consume(purchase.purchaseToken).timeout(operationTimeout);
      return (credited: credited, consumed: consumed);
    } on Object {
      return (credited: credited, consumed: false);
    }
  }

  Future<BillingResult> buy(String productId) => _exclusive(() async {
    if (CreditCatalog.byId(productId) == null) throw const BillingException('بسته اعتبار ناشناخته است.');
    await _safe(_connect);
    // A stalled billing activity must not leave the shop busy forever. A timeout
    // is an unknown purchase outcome, so the UI explicitly directs the user to restore.
    final purchase = await _safe(() => gateway.purchase(productId).timeout(operationTimeout));
    _validate(purchase, productId);
    final result = await _creditAndConsume(purchase, productId);
    return BillingResult(credited: result.credited ? 1 : 0, alreadyCredited: result.credited ? 0 : 1, consumptionPending: !result.consumed);
  });

  Future<BillingResult> restorePurchases() => _exclusive(() async {
    await _safe(_connect);
    final purchases = await _safe(() => gateway.purchasedProducts().timeout(operationTimeout));
    var credited = 0, existing = 0, skipped = 0;
    var pending = false;
    for (final purchase in purchases) {
      final product = CreditCatalog.byId(purchase.productId);
      if (product == null || !purchase.purchased || purchase.packageName != packageName ||
          purchase.signature.trim().isEmpty || purchase.purchaseToken.trim().isEmpty ||
          purchase.purchaseToken.length > 512) {
        skipped++;
        continue;
      }
      final result = await _creditAndConsume(purchase, product.id);
      if (result.credited) { credited++; } else { existing++; }
      if (!result.consumed) pending = true;
    }
    return BillingResult(credited: credited, alreadyCredited: existing,
        consumptionPending: pending, skipped: skipped);
  });

  Future<T> _safe<T>(Future<T> Function() action) async {
    try { return await action(); }
    on PlatformException catch (error) {
      _connected = false;
      throw BillingException(switch (error.code) {
        'PURCHASE_CANCELLED' => 'پرداخت لغو شد. اعتباری تغییر نکرد.',
        'FAILED_TO_BEGIN_FLOW' => 'بازار نتوانست پرداخت را باز کند. نصب، ورود و به‌روز بودن بازار را بررسی کن.',
        'PAYMENT_CONNECTION_IS_NOT_CONNECTED' => 'ارتباط با بازار قطع شد. دوباره تلاش کن.',
        'QUERY_GET_IN_APP_SKU_DETAILS_FAILED' => 'اطلاعات بسته‌ها دریافت نشد. محصولات پنل بازار و اتصال اینترنت را بررسی کن.',
        _ => 'عملیات پرداخت کامل نشد. اتصال اینترنت را بررسی کن؛ برای خرید احتمالی از بازیابی خریدها استفاده کن.',
      }, cancelled: error.code == 'PURCHASE_CANCELLED');
    } on TimeoutException {
      throw const BillingException('بازار به‌موقع پاسخ نداد. پیش از پرداخت دوباره، خریدهای قبلی را بازیابی کن.');
    } on BillingException { rethrow; }
    on LocalDataException { rethrow; }
    on Object {
      throw const BillingException('ارتباط با بازار کامل نشد. برای بررسی خرید احتمالی، بازیابی خریدها را بزن.');
    }
  }

  Future<void> disconnect() async {
    _disposed = true;
    if (_busy || _connecting != null) return;
    if (!_connected) return;
    _connected = false;
    try { await gateway.disconnect(); } on Object {
      // Do not log platform exception details: they can contain purchase data.
    }
  }
}
