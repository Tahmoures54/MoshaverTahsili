import 'dart:async';

import 'package:cafebazaar_billing/cafebazaar_billing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'education_store.dart';

// -----------------------------------------------------------------------------
// Exceptions and models
// -----------------------------------------------------------------------------

class BillingException implements Exception {
  const BillingException(this.message, {this.cancelled = false});

  final String message;
  final bool cancelled;

  @override
  String toString() => message;
}

/// Purchase information returned by the gateway.
///
/// The class name is retained for compatibility.
/// Its presence alone does NOT prove cryptographic verification.
///
/// The gateway/backend must verify purchase authenticity before wallet credit
/// is trusted. Checking that a signature string is present is insufficient.
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

  /// Number of credited packages, not number of individual credits.
  final int credited;

  final int alreadyCredited;
  final int skipped;
  final int failed;
  final bool consumptionPending;

  String get message {
    final messages = <String>[];

    if (credited > 0) {
      messages.add('$credited بسته پر به کیسه پرهای سیمرغ اضافه شد.');
    }

    if (alreadyCredited > 0) {
      messages.add(
        '$alreadyCredited خرید قبلاً ثبت شده بود؛ '
        'پر تکراری اضافه نشد.',
      );
    }

    if (consumptionPending) {
      messages.add(
        'نهایی‌سازی بعضی خریدها در بازار تأیید نشد. '
        'اعتبار ثبت‌شده حفظ شده است؛ '
        'بعداً بازیابی خریدها را اجرا کن.',
      );
    }

    if (failed > 0) {
      messages.add(
        '$failed خرید بررسی یا پردازش کامل نشد. '
        'پیش از پرداخت دوباره، بازیابی خریدها را اجرا کن.',
      );
    }

    if (skipped > 0) {
      messages.add('$skipped مورد نامعتبر یا نامرتبط پردازش نشد.');
    }

    if (messages.isEmpty) {
      return 'خرید مصرف‌نشده‌ای برای بازیابی پیدا نشد.';
    }

    return messages.join('\n');
  }
}

// -----------------------------------------------------------------------------
// Gateway contract
// -----------------------------------------------------------------------------

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

// -----------------------------------------------------------------------------
// Cafe Bazaar plugin adapter
// -----------------------------------------------------------------------------

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
            'اتصال به بازار برقرار نشد. '
            'نصب و به‌روز بودن بازار را بررسی کن.',
          ),
        );
      }
    }

    // Timeout is managed by BazaarBillingService.
    // A timeout here would hide an underlying connection still in progress.
    await Future.wait<void>([
      Future<void>.sync(
        () => CafeBazaarBilling.connect(
          publicKey,
          onSucceed: succeed,
          onFailed: fail,
          onDisconnected: () {
            fail();
            onDisconnected();
          },
        ),
      ),
      connected.future,
    ], eagerError: true);
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
    final info = await CafeBazaarBilling.purchase(productId);

    return _map(info);
  }

  @override
  Future<List<VerifiedPurchase>> purchasedProducts() async {
    final purchases = await CafeBazaarBilling.getAllPurchasedProducts();

    return purchases.map(_map).toList(growable: false);
  }

  @override
  Future<List<ShopProduct>> products(List<String> ids) async {
    final details = await CafeBazaarBilling.getInAppSkuDetails(ids);
    final requested = ids.toSet();
    final seen = <String>{};
    final result = <ShopProduct>[];

    for (final item in details) {
      final product = CreditCatalog.byId(item.sku);
      final price = item.price.trim();

      if (product == null ||
          !requested.contains(item.sku) ||
          item.type != 'inapp' ||
          price.isEmpty ||
          price.length > 256 ||
          !seen.add(item.sku)) {
        continue;
      }

      result.add(ShopProduct(product, price));
    }

    return result;
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

// -----------------------------------------------------------------------------
// Shared in-memory operation state
// -----------------------------------------------------------------------------

class _BillingOperationState {
  bool busy = false;

  /// Set when a payment may have occurred but its outcome is not reconciled.
  ///
  /// This is not durable. Persist equivalent state in a production wallet or
  /// backend if it must survive application termination.
  bool recoveryRequired = false;

  /// Completes only when the original gateway Future actually completes.
  ///
  /// Future.timeout does not cancel the native operation.
  Future<void>? pendingGateway;
}

// -----------------------------------------------------------------------------
// Billing service
// -----------------------------------------------------------------------------

class BazaarBillingService {
  BazaarBillingService(
    this.store, {
    BazaarGateway? gateway,
    String? publicKey,
    bool? catalogConfirmed,
    bool? supportedPlatform,
    this.operationTimeout = const Duration(seconds: 30),
  }) : gateway = gateway ?? PluginBazaarGateway(),
       publicKey =
           (publicKey ?? const String.fromEnvironment('BAZAAR_RSA_PUBLIC_KEY'))
               .trim(),
       catalogConfirmed =
           catalogConfirmed ??
           const bool.fromEnvironment('BAZAAR_CATALOG_CONFIRMED'),
       supportedPlatform =
           supportedPlatform ??
           (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    if (operationTimeout <= Duration.zero) {
      throw ArgumentError.value(
        operationTimeout,
        'operationTimeout',
        'Must be greater than zero.',
      );
    }

    _state = _states[store] ??= _BillingOperationState();
  }

  static final Expando<_BillingOperationState> _states =
      Expando<_BillingOperationState>('bazaarBillingState');

  static const String packageName = 'ir.moshaver.tahsili';

  final EducationStore store;
  final BazaarGateway gateway;

  final String publicKey;
  final bool catalogConfirmed;
  final bool supportedPlatform;
  final Duration operationTimeout;

  late final _BillingOperationState _state;

  bool _connected = false;
  bool _disposed = false;

  int _connectionGeneration = 0;

  Future<void>? _connecting;
  Future<void>? _disconnecting;

  bool get isBusy {
    return _state.busy ||
        _state.pendingGateway != null ||
        _disconnecting != null;
  }

  bool get requiresPurchaseRecovery => _state.recoveryRequired;

  bool get isConfigured {
    return publicKey.isNotEmpty && catalogConfirmed && supportedPlatform;
  }

  String get configurationMessage {
    if (!supportedPlatform) {
      return 'خرید درون‌برنامه‌ای فقط در نسخه اندروید '
          'و از طریق بازار در دسترس است.';
    }

    if (publicKey.isEmpty) {
      return 'کلید عمومی بازار در این نسخه تنظیم نشده است؛ '
          'خرید فعال نیست.';
    }

    if (!catalogConfirmed) {
      return 'شناسه محصولات هنوز با پروژه مرجع و پنل بازار '
          'تأیید نشده‌اند؛ پرداخت غیرفعال است.';
    }

    return '';
  }

  // ---------------------------------------------------------------------------
  // Gateway execution
  // ---------------------------------------------------------------------------

  /// Applies a caller-facing timeout while keeping the underlying operation
  /// registered until it actually finishes.
  ///
  /// Late purchase results are not automatically credited here. They are
  /// reconciled through restorePurchases.
  Future<T> _gatewayCall<T>(Future<T> Function() action) async {
    if (_state.pendingGateway != null) {
      throw const BillingException(
        'عملیات قبلی بازار هنوز پایان نیافته است. '
        'پس از بسته‌شدن پنجره پرداخت یا پایان عملیات، '
        'دوباره تلاش کن.',
      );
    }

    final source = Future<T>.sync(action);

    // Attach an error handler immediately so a late native error is observed.
    final settled = source.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );

    _state.pendingGateway = settled;

    unawaited(
      settled.then<void>((_) {
        if (identical(_state.pendingGateway, settled)) {
          _state.pendingGateway = null;
        }

        if (_disposed) {
          unawaited(_disconnectIfPossible());
        }
      }),
    );

    return source.timeout(operationTimeout);
  }

  // ---------------------------------------------------------------------------
  // Connection
  // ---------------------------------------------------------------------------

  Future<void> _connect() async {
    if (_disposed) {
      throw const BillingException('سرویس پرداخت بسته شده است.');
    }

    if (!isConfigured) {
      throw BillingException(configurationMessage);
    }

    if (_connected) return;

    final active = _connecting;

    if (active != null) {
      await active;
      return;
    }

    final generation = ++_connectionGeneration;
    var disconnected = false;

    final future = () async {
      await _gatewayCall<void>(
        () => gateway.connect(
          publicKey,
          onDisconnected: () {
            disconnected = true;

            if (generation == _connectionGeneration) {
              _connected = false;
            }
          },
        ),
      );

      if (_disposed || generation != _connectionGeneration || disconnected) {
        throw const BillingException(
          'اتصال بازار دیگر فعال نیست. دوباره تلاش کن.',
        );
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

  Future<T> _exclusive<T>(Future<T> Function() action) async {
    if (_disposed) {
      throw const BillingException('سرویس پرداخت بسته شده است.');
    }

    if (isBusy) {
      throw const BillingException(
        'یک عملیات بازار هنوز در حال انجام است. کمی صبر کن.',
      );
    }

    if (store.walletError != null) {
      throw LocalDataException(store.walletError!);
    }

    _state.busy = true;

    try {
      return await action();
    } finally {
      _state.busy = false;

      if (_disposed) {
        unawaited(_disconnectIfPossible());
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Catalog
  // ---------------------------------------------------------------------------

  Future<List<ShopProduct>> loadProducts() {
    return _exclusive(() async {
      await _safe<void>(_connect);

      final ids = CreditCatalog.products
          .map((product) => product.id)
          .toSet()
          .toList(growable: false);

      final details = await _safe<List<ShopProduct>>(
        () => _gatewayCall(() => gateway.products(ids)),
      );

      // Validate custom gateways as well as the plugin adapter.
      final seen = <String>{};
      final result = <ShopProduct>[];

      for (final item in details) {
        final catalogProduct = CreditCatalog.byId(item.product.id);
        final price = item.price.trim();

        if (catalogProduct == null ||
            !ids.contains(catalogProduct.id) ||
            price.isEmpty ||
            price.length > 256 ||
            !seen.add(catalogProduct.id)) {
          continue;
        }

        result.add(ShopProduct(catalogProduct, price));
      }

      return result;
    });
  }

  // ---------------------------------------------------------------------------
  // Purchase shape checks
  // ---------------------------------------------------------------------------

  bool _hasValidPurchaseShape(
    VerifiedPurchase purchase,
    String expectedProduct,
  ) {
    return purchase.purchased &&
        purchase.productId == expectedProduct &&
        purchase.packageName == packageName &&
        purchase.purchaseToken.trim().isNotEmpty &&
        purchase.purchaseToken.length <= 512 &&
        purchase.signature.trim().isNotEmpty &&
        purchase.signature.length <= 16 * 1024;
  }

  void _validate(VerifiedPurchase purchase, String expectedProduct) {
    if (!_hasValidPurchaseShape(purchase, expectedProduct)) {
      throw const BillingException(
        'اطلاعات خرید برای این برنامه معتبر نیست؛ '
        'در این مرحله پری اضافه نشد. '
        'برای بررسی وضعیت، بازیابی خریدها را اجرا کن.',
      );
    }
  }

  bool _isValidRestoredPurchase(VerifiedPurchase purchase) {
    return CreditCatalog.byId(purchase.productId) != null &&
        _hasValidPurchaseShape(purchase, purchase.productId);
  }

  // ---------------------------------------------------------------------------
  // Credit first, consume second
  // ---------------------------------------------------------------------------

  Future<({bool credited, bool consumed})> _creditAndConsume(
    VerifiedPurchase purchase,
    String productId,
  ) async {
    final product = CreditCatalog.byId(productId);

    if (product == null || product.credits <= 0) {
      throw const BillingException('شناسه یا مقدار اعتبار بسته پر معتبر نیست.');
    }

    _validate(purchase, productId);

    // Required EducationStore guarantees:
    //
    // 1. Persist token and wallet increment atomically.
    // 2. The same token must never increment credits twice.
    // 3. A token must not be reassigned to another product.
    // 4. Backup import must not overwrite this protected ledger.
    //
    // Authenticity must be verified by a trusted gateway/backend.
    final credited = await store.grantProduct(
      productId: productId,
      purchaseToken: purchase.purchaseToken,
      creditsToAdd: product.credits,
    );

    try {
      final consumed = await _gatewayCall<bool>(
        () => gateway.consume(purchase.purchaseToken),
      );

      return (credited: credited, consumed: consumed);
    } on Object {
      // Never undo a persisted grant because consumption failed.
      return (credited: credited, consumed: false);
    }
  }

  // ---------------------------------------------------------------------------
  // Buy
  // ---------------------------------------------------------------------------

  Future<BillingResult> buy(String productId) {
    return _exclusive(() async {
      final product = CreditCatalog.byId(productId);

      if (product == null || product.credits <= 0) {
        throw const BillingException('بسته پر سیمرغ ناشناخته یا نامعتبر است.');
      }

      if (_state.recoveryRequired) {
        throw const BillingException(
          'وضعیت خرید قبلی هنوز کامل بررسی نشده است. '
          'پیش از پرداخت دوباره، بازیابی خریدها را اجرا کن.',
        );
      }

      await _safe<void>(_connect);

      // From this point onward a payment might have occurred.
      _state.recoveryRequired = true;

      VerifiedPurchase purchase;

      try {
        purchase = await _safe<VerifiedPurchase>(
          () => _gatewayCall(() => gateway.purchase(productId)),
        );
      } on BillingException catch (error) {
        if (error.cancelled) {
          _state.recoveryRequired = false;
        }

        rethrow;
      }

      _validate(purchase, productId);

      // Storage failures propagate. Recovery remains required.
      final result = await _creditAndConsume(purchase, productId);

      _state.recoveryRequired = !result.consumed;

      return BillingResult(
        credited: result.credited ? 1 : 0,
        alreadyCredited: result.credited ? 0 : 1,
        consumptionPending: !result.consumed,
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Restore
  // ---------------------------------------------------------------------------

  Future<BillingResult> restorePurchases() {
    return _exclusive(() async {
      await _safe<void>(_connect);

      final purchases = await _safe<List<VerifiedPurchase>>(
        () => _gatewayCall(gateway.purchasedProducts),
      );

      var credited = 0;
      var existing = 0;
      var skipped = 0;
      var failed = 0;
      var pending = false;

      final unique = <String, VerifiedPurchase>{};
      final conflictingTokens = <String>{};

      for (final purchase in purchases) {
        if (!_isValidRestoredPurchase(purchase)) {
          skipped++;
          continue;
        }

        final token = purchase.purchaseToken;
        final previous = unique[token];

        if (previous == null) {
          unique[token] = purchase;
          continue;
        }

        if (previous.productId != purchase.productId ||
            previous.packageName != purchase.packageName) {
          conflictingTokens.add(token);
        }

        // Exact-token duplicates are processed once.
      }

      for (final token in conflictingTokens) {
        unique.remove(token);
        failed++;
      }

      final validPurchases = unique.values.toList(growable: false);

      for (var index = 0; index < validPurchases.length; index++) {
        // A timed-out consume may still be running natively.
        // Do not start another native call over it.
        if (_state.pendingGateway != null) {
          failed += validPurchases.length - index;
          break;
        }

        final purchase = validPurchases[index];

        try {
          final result = await _creditAndConsume(purchase, purchase.productId);

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
          _state.recoveryRequired = true;

          // Stop on wallet persistence failure.
          rethrow;
        } on Object {
          _state.recoveryRequired = true;

          // Unexpected grant errors are not treated as harmless skips.
          throw const BillingException(
            'ثبت یکی از خریدها کامل نشد. '
            'خریدهای قبلی ممکن است ثبت شده باشند؛ '
            'پیش از پرداخت مجدد، بازیابی خریدها را اجرا کن.',
          );
        }
      }

      // Skipped records are not enough to safely reconcile an uncertain
      // payment. Require a clean restore before enabling another purchase.
      _state.recoveryRequired =
          pending || failed > 0 || skipped > 0 || _state.pendingGateway != null;

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

  Future<T> _safe<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on MissingPluginException {
      _connected = false;

      throw const BillingException(
        'درگاه پرداخت بازار در این نسخه در دسترس نیست.',
      );
    } on PlatformException catch (error) {
      _connected = false;

      throw BillingException(switch (error.code) {
        'PURCHASE_CANCELLED' => 'پرداخت لغو شد؛ این عملیات اعتباری اضافه نکرد.',
        'FAILED_TO_BEGIN_FLOW' =>
          'بازار نتوانست پرداخت را باز کند. '
              'نصب، ورود و به‌روز بودن بازار را بررسی کن.',
        'PAYMENT_CONNECTION_IS_NOT_CONNECTED' =>
          'ارتباط با بازار قطع شد. '
              'برای بررسی پرداخت احتمالی، خریدها را بازیابی کن.',
        'QUERY_GET_IN_APP_SKU_DETAILS_FAILED' =>
          'اطلاعات بسته‌ها دریافت نشد. '
              'محصولات پنل بازار و اتصال را بررسی کن.',
        _ =>
          'عملیات بازار کامل نشد. '
              'پیش از پرداخت دوباره، بازیابی خریدها را اجرا کن.',
      }, cancelled: error.code == 'PURCHASE_CANCELLED');
    } on TimeoutException {
      _connected = false;

      throw const BillingException(
        'بازار به‌موقع پاسخ نداد. '
        'این وضعیت به معنی لغوشدن پرداخت نیست. '
        'پس از پایان عملیات قبلی، خریدها را بازیابی کن.',
      );
    } on BillingException {
      rethrow;
    } on LocalDataException {
      rethrow;
    } on Object {
      _connected = false;

      throw const BillingException(
        'ارتباط با بازار کامل نشد. '
        'برای بررسی خرید احتمالی، بازیابی خریدها را اجرا کن.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Disposal
  // ---------------------------------------------------------------------------

  Future<void> _disconnectIfPossible() async {
    final active = _disconnecting;

    if (active != null) {
      await active;
      return;
    }

    if (_state.busy || _state.pendingGateway != null || _connecting != null) {
      return;
    }

    // Attempt cleanup even if a timeout made _connected false.
    // Native resources may still exist.
    _connected = false;
    _connectionGeneration++;

    final future = () async {
      try {
        await gateway.disconnect();
      } on Object {
        // Do not log raw billing exceptions or purchase information.
      }
    }();

    _disconnecting = future;

    try {
      await future;
    } finally {
      if (identical(_disconnecting, future)) {
        _disconnecting = null;
      }
    }
  }

  /// Marks this service as disposed.
  ///
  /// If an operation is still running, cleanup is deferred.
  /// This Future does not necessarily wait for that deferred cleanup.
  Future<void> disconnect() async {
    _disposed = true;

    await _disconnectIfPossible();
  }
}
