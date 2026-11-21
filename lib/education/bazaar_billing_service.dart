
import 'dart:async';

import 'package:cafebazaar_billing/cafebazaar_billing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'education_store.dart';

class BillingException implements Exception {
  const BillingException(
    this.message, {
    this.cancelled = false,
  });

  final String message;
  final bool cancelled;

  @override
  String toString() => message;
}

class VerifiedPurchase {
  const VerifiedPurchase({
    required this.productId,
    required this.purchaseToken,
    required this.packageName,
    required this.signature,
    required this.purchased,
  });

  final String productId;
  final String purchaseToken;
  final String packageName;
  final String signature;
  final bool purchased;
}

class ShopProduct {
  const ShopProduct(this.product, this.price);

  final CreditProduct product;
  final String price;
}

class BillingResult {
  const BillingResult({
    this.credited = 0,
    this.alreadyCredited = 0,
    this.consumptionPending = false,
    this.skipped = 0,
    this.failed = 0,
  });

  final int credited;
  final int alreadyCredited;
  final int skipped;
  final int failed;
  final bool consumptionPending;

  String get message {
    if (consumptionPending) {
      if (credited > 0) {
        return '$credited بسته پر ثبت شد؛ اما نهایی‌سازی بعضی خریدها در بازار کامل نشد. بعداً بازیابی خریدها را اجرا کن.';
      }

      return 'اعتبار خریدهای قبلی حفظ شده است، اما نهایی‌سازی خرید در بازار کامل نشد. بعداً بازیابی خریدها را اجرا کن.';
    }

    if (failed > 0) {
      return 'بازیابی خریدها کامل نشد. $failed خرید نیازمند بررسی است. دوباره تلاش کن.';
    }

    if (credited > 0 && alreadyCredited > 0) {
      return '$credited بسته پر جدید ثبت شد. $alreadyCredited خرید قبلاً ثبت شده بود و دوباره شارژ نشد.';
    }

    if (credited > 0) {
      return '$credited بسته پر به کیسه پرهای سیمرغ اضافه شد.';
    }

    if (alreadyCredited > 0) {
      return 'این خریدها قبلاً ثبت شده‌اند؛ پر تکراری اضافه نشد.';
    }

    if (skipped > 0) {
      return 'خرید قابل تأییدی برای این برنامه پیدا نشد. پری اضافه نشد.';
    }

    return 'خرید مصرف‌نشده‌ای برای بازیابی پیدا نشد.';
  }
}

/// مرز قابل‌آزمایش ارتباط با بازار.
abstract class BazaarGateway {
  Future<void> connect(
    String publicKey, {
    required VoidCallback onDisconnected,
  });

  Future<VerifiedPurchase> purchase(String productId);

  Future<List<VerifiedPurchase>> purchasedProducts();

  Future<List<ShopProduct>> products(List<String> ids);

  Future<bool> consume(String token);

  Future<void> disconnect();
}

/// پیاده‌سازی واقعی درگاه بازار.
class PluginBazaarGateway implements BazaarGateway {
  @override
  Future<void> connect(
    String publicKey, {
    required VoidCallback onDisconnected,
  }) async {
    final connected = Completer<void>();

    void succeed() {
      if (!connected.isCompleted) {
        connected.complete();
      }
    }

    void fail() {
      if (!connected.isCompleted) {
        connected.completeError(
          const BillingException(
            'اتصال به بازار برقرار نشد. بازار را به‌روز کن و دوباره تلاش کن.',
          ),
        );
      }
    }

    await Future.wait<void>([
      CafeBazaarBilling.connect(
        publicKey,
        onSucceed: succeed,
        onFailed: fail,
        onDisconnected: () {
          fail();
          onDisconnected();
        },
      ),
      connected.future,
    ]).timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        throw const BillingException(
          'بازار به‌موقع پاسخ نداد. اتصال اینترنت و نصب بازار را بررسی کن.',
        );
      },
    );
  }

  VerifiedPurchase _map(PurchaseInfo info) {
    return VerifiedPurchase(
      productId: info.productId,
      purchaseToken: info.purchaseToken,
      packageName: info.packageName,
      signature: info.dataSignature,
      purchased: info.purchaseState == PurchaseState.PURCHASED,
    );
  }

  @override
  Future<VerifiedPurchase> purchase(String productId) async {
    return _map(await CafeBazaarBilling.purchase(productId));
  }

  @override
  Future<List<VerifiedPurchase>> purchasedProducts() async {
    final items = await CafeBazaarBilling.getAllPurchasedProducts();
    return items.map(_map).toList();
  }

  @override
  Future<List<ShopProduct>> products(List<String> ids) async {
    final details = await CafeBazaarBilling.getInAppSkuDetails(ids);

    return [
      for (final item in details)
        if (CreditCatalog.byId(item.sku) != null &&
            item.type == 'inapp' &&
            item.price.isNotEmpty)
          ShopProduct(
            CreditCatalog.byId(item.sku)!,
            item.price,
          ),
    ];
  }

  @override
  Future<bool> consume(String token) {
    return CafeBazaarBilling.consume(token);
  }

  @override
  Future<void> disconnect() {
    return CafeBazaarBilling.disconnect();
  }
}

class BazaarBillingService {
  BazaarBillingService(
    this.store, {
    BazaarGateway? gateway,
    String? publicKey,
    bool? catalogConfirmed,
    bool? supportedPlatform,
    this.operationTimeout = const Duration(seconds: 30),
  })  : gateway = gateway ?? PluginBazaarGateway(),
        publicKey = (publicKey ??
                const String.fromEnvironment('BAZAAR_RSA_PUBLIC_KEY'))
            .trim(),
        catalogConfirmed = catalogConfirmed ??
            const bool.fromEnvironment('BAZAAR_CATALOG_CONFIRMED'),
        supportedPlatform = supportedPlatform ??
            (!kIsWeb &&
                defaultTargetPlatform == TargetPlatform.android);

  final EducationStore store;
  final BazaarGateway gateway;

  final String publicKey;
  final bool catalogConfirmed;
  final bool supportedPlatform;
  final Duration operationTimeout;

  static const String packageName = 'ir.moshaver.tahsili';

  bool _connected = false;
  bool _busy = false;
  bool _disposed = false;

  Future<void>? _connecting;

  bool get isBusy => _busy;

  bool get isConfigured {
    return publicKey.isNotEmpty &&
        catalogConfirmed &&
        supportedPlatform;
  }

  String get configurationMessage {
    if (!supportedPlatform) {
      return 'خرید درون‌برنامه‌ای فقط در نسخه اندروید و از طریق بازار در دسترس است.';
    }

    if (publicKey.isEmpty) {
      return 'کلید عمومی بازار در این نسخه تنظیم نشده است؛ خرید فعال نیست.';
    }

    if (!catalogConfirmed) {
      return 'شناسه محصولات هنوز با پروژه مرجع و پنل بازار تأیید نشده‌اند؛ پرداخت غیرفعال است.';
    }

    return '';
  }

  // ---------------------------------------------------------------------------
  // Connection
  // ---------------------------------------------------------------------------

  Future<void> _connect() async {
    if (!isConfigured) {
      throw BillingException(configurationMessage);
    }

    if (_disposed) {
      throw const BillingException('سرویس پرداخت بسته شده است.');
    }

    if (_connected) return;

    final active = _connecting;
    if (active != null) {
      return active;
    }

    final future = () async {
      await gateway.connect(
        publicKey,
        onDisconnected: () {
          _connected = false;
        },
      );

      if (_disposed) {
        throw const BillingException('سرویس پرداخت بسته شده است.');
      }

      _connected = true;
    }();

    _connecting = future;

    try {
      await future;
    } finally {
      if (identical(_connecting, future)) {
        _connecting = null;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Exclusive operation guard
  // ---------------------------------------------------------------------------

  Future<T> _exclusive<T>(
    Future<T> Function() action,
  ) async {
    if (_disposed) {
      throw const BillingException('صفحه خرید بسته شده است.');
    }

    if (_busy) {
      throw const BillingException(
        'یک عملیات پرداخت در حال انجام است. کمی صبر کن.',
      );
    }

    if (store.walletError != null) {
      throw LocalDataException(store.walletError!);
    }

    _busy = true;

    try {
      return await action();
    } finally {
      _busy = false;

      if (_disposed) {
        unawaited(_disconnectIfPossible());
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Product catalog
  // ---------------------------------------------------------------------------

  Future<List<ShopProduct>> loadProducts() {
    return _exclusive(() async {
      await _safe(_connect);

      return _safe(
        () => gateway
            .products(
              CreditCatalog.products.map((p) => p.id).toList(),
            )
            .timeout(operationTimeout),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Purchase validation
  // ---------------------------------------------------------------------------

  void _validate(
    VerifiedPurchase purchase,
    String expectedProduct,
  ) {
    if (!purchase.purchased ||
        purchase.productId != expectedProduct ||
        purchase.packageName != packageName ||
        purchase.purchaseToken.trim().isEmpty ||
        purchase.purchaseToken.length > 512 ||
        purchase.signature.trim().isEmpty) {
      throw const BillingException(
        'خرید برای این برنامه قابل تأیید نیست؛ پری اضافه نشد. با بازیابی خریدها دوباره بررسی کن.',
      );
    }
  }

  bool _isValidRestoredPurchase(VerifiedPurchase purchase) {
    final product = CreditCatalog.byId(purchase.productId);

    return product != null &&
        purchase.purchased &&
        purchase.packageName == packageName &&
        purchase.purchaseToken.trim().isNotEmpty &&
        purchase.purchaseToken.length <= 512 &&
        purchase.signature.trim().isNotEmpty;
  }

  // ---------------------------------------------------------------------------
  // Credit and consume
  // ---------------------------------------------------------------------------

  Future<({bool credited, bool consumed})> _creditAndConsume(
    VerifiedPurchase purchase,
    String productId,
  ) async {
    final product = CreditCatalog.byId(productId);

    if (product == null) {
      throw const BillingException(
        'شناسه بسته پر سیمرغ معتبر نیست.',
      );
    }

    _validate(purchase, productId);

    // ابتدا توکن یکتا و اعتبار در حافظه پایدار ثبت می‌شوند.
    // سپس خرید در بازار مصرف می‌شود.
    //
    // اگر برنامه در این فاصله بسته شود، بازیابی خریدها می‌تواند
    // همان توکن را دوباره بررسی کند؛ ثبت تکراری نباید اعتبار جدید بسازد.
    final credited = await store.grantProduct(
      productId: productId,
      purchaseToken: purchase.purchaseToken,
      creditsToAdd: product.credits,
    );

    try {
      final consumed = await gateway
          .consume(purchase.purchaseToken)
          .timeout(operationTimeout);

      return (
        credited: credited,
        consumed: consumed,
      );
    } on Object {
      // اعتبار قبلاً ثبت شده است.
      // خطای مصرف نباید باعث حذف یا برگشت اعتبار شود.
      return (
        credited: credited,
        consumed: false,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Buy
  // ---------------------------------------------------------------------------

  Future<BillingResult> buy(String productId) {
    return _exclusive(() async {
      if (CreditCatalog.byId(productId) == null) {
        throw const BillingException(
          'بسته پر سیمرغ ناشناخته است.',
        );
      }

      await _safe(_connect);

      // در صورت timeout نتیجه خرید نامشخص است.
      // قبل از خرید مجدد، بازیابی خریدها باید اجرا شود.
      final purchase = await _safe(
        () => gateway
            .purchase(productId)
            .timeout(operationTimeout),
      );

      _validate(purchase, productId);

      final result = await _creditAndConsume(
        purchase,
        productId,
      );

      return BillingResult(
        credited: result.credited ? 1 : 0,
        alreadyCredited: result.credited ? 0 : 1,
        consumptionPending: !result.consumed,
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Restore purchases
  // ---------------------------------------------------------------------------

  Future<BillingResult> restorePurchases() {
    return _exclusive(() async {
      await _safe(_connect);

      final purchases = await _safe(
        () => gateway
            .purchasedProducts()
            .timeout(operationTimeout),
      );

      var credited = 0;
      var existing = 0;
      var skipped = 0;
      var failed = 0;
      var pending = false;

      for (final purchase in purchases) {
        if (!_isValidRestoredPurchase(purchase)) {
          skipped++;
          continue;
        }

        final product = CreditCatalog.byId(purchase.productId);

        if (product == null) {
          skipped++;
          continue;
        }

        try {
          final result = await _creditAndConsume(
            purchase,
            product.id,
          );

          if (result.credited) {
            credited++;
          } else {
            existing++;
          }

          if (!result.consumed) {
            pending = true;
          }
        } on BillingException {
          failed++;
        } on LocalDataException {
          // خطای ذخیره‌سازی محلی مهم است؛
          // ادامه پردازش می‌تواند وضعیت کیف پول را مبهم کند.
          rethrow;
        }
      }

      return BillingResult(
        credited: credited,
        alreadyCredited: existing,
        consumptionPending: pending,
        skipped: skipped,
        failed: failed,
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Error normalization
  // ---------------------------------------------------------------------------

  Future<T> _safe<T>(
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } on PlatformException catch (error) {
      _connected = false;

      throw BillingException(
        switch (error.code) {
          'PURCHASE_CANCELLED' =>
            'پرداخت لغو شد. موجودی پر تغییر نکرد.',
          'FAILED_TO_BEGIN_FLOW' =>
            'بازار نتوانست پرداخت را باز کند. نصب، ورود و به‌روز بودن بازار را بررسی کن.',
          'PAYMENT_CONNECTION_IS_NOT_CONNECTED' =>
            'ارتباط با بازار قطع شد. دوباره تلاش کن.',
          'QUERY_GET_IN_APP_SKU_DETAILS_FAILED' =>
            'اطلاعات بسته‌ها دریافت نشد. محصولات پنل بازار و اتصال اینترنت را بررسی کن.',
          _ =>
            'عملیات پرداخت کامل نشد. اتصال اینترنت را بررسی کن؛ برای خرید احتمالی از بازیابی خریدها استفاده کن.',
        },
        cancelled: error.code == 'PURCHASE_CANCELLED',
      );
    } on TimeoutException {
      _connected = false;

      throw const BillingException(
        'بازار به‌موقع پاسخ نداد. پیش از پرداخت دوباره، خریدهای قبلی را بازیابی کن.',
      );
    } on BillingException {
      rethrow;
    } on LocalDataException {
      rethrow;
    } on Object {
      throw const BillingException(
        'ارتباط با بازار کامل نشد. برای بررسی خرید احتمالی، بازیابی خریدها را بزن.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Disconnect and disposal
  // ---------------------------------------------------------------------------

  Future<void> _disconnectIfPossible() async {
    if (_busy || _connecting != null || !_connected) {
      return;
    }

    _connected = false;

    try {
      await gateway.disconnect();
    } on Object {
      // اطلاعات خام خطای درگاه در لاگ ثبت نمی‌شود؛
      // ممکن است حاوی داده خرید باشد.
    }
  }

  Future<void> disconnect() async {
    _disposed = true;

    await _disconnectIfPossible();
  }
}
