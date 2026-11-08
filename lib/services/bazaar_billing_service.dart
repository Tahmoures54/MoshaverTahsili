import 'package:cafebazaar_billing/cafebazaar_billing.dart';
import 'package:flutter/foundation.dart';

import 'local_first_store.dart';

/// Cafe Bazaar billing for the store-distributed Android build.
/// The web backend and its Zibal payment flow are intentionally untouched.
class BazaarBillingService {
  BazaarBillingService(this._store);

  final LocalFirstStore _store;
  static const String _publicKey =
      String.fromEnvironment('BAZAAR_RSA_PUBLIC_KEY');

  bool _connected = false;

  bool get isConfigured => _publicKey.trim().isNotEmpty;

  Future<void> connect() async {
    if (_connected) return;
    if (!isConfigured) {
      throw const BazaarBillingException(
        'کلید عمومی پرداخت بازار در بیلد تنظیم نشده است.',
      );
    }
    await CafeBazaarBilling.connect(_publicKey);
    _connected = true;
  }

  Future<void> buy(String productId) async {
    await connect();
    // All three plans are finite credit packs. Keep all three products configured as consumable
    // in-app products in the Bazaar console.
    final info = await CafeBazaarBilling.purchase(productId);
    if (info.purchaseState != PurchaseState.PURCHASED ||
        info.productId != productId ||
        info.purchaseToken.trim().isEmpty) {
      throw const BazaarBillingException(
        'خرید توسط بازار تأیید نشد؛ هیچ اعتباری اضافه نشد.',
      );
    }

    final credits = _productCredits(productId);
    if (credits == null) {
      throw BazaarBillingException('محصول ناشناخته: $productId');
    }

    // Persist the entitlement before consuming the Bazaar token so a repeated
    // callback cannot grant the same purchase twice.
    await _store.grantProduct(
      productId: productId,
      purchaseToken: info.purchaseToken,
      creditsToAdd: credits,
    );

    // Every package is a finite consumable entitlement. The local ledger
    // records the token before consuming it to prevent duplicate callbacks.
    if (credits > 0) {
      try {
        final consumed = await CafeBazaarBilling.consume(info.purchaseToken);
        if (!consumed) {
          debugPrint('[BazaarBilling] مصرف توکن انجام نشد؛ خرید محلی ثبت شده است.');
        }
      } catch (e) {
        // The entitlement is already committed locally. Do not tell the user
        // the purchase failed just because Bazaar token consumption errored.
        debugPrint('[BazaarBilling] مصرف توکن ناموفق بود؛ اعتبار محلی ثبت شده است: $e');
      }
    }
  }

  Future<void> restorePurchases() async {
    await connect();
    final owned = await CafeBazaarBilling.getAllPurchasedProducts();
    for (final purchase in owned) {
      if (purchase.purchaseState != PurchaseState.PURCHASED ||
          purchase.purchaseToken.trim().isEmpty) {
        continue;
      }
      final credits = _productCredits(purchase.productId);
      if (credits == null) continue;
      await _store.grantProduct(
        productId: purchase.productId,
        purchaseToken: purchase.purchaseToken,
        creditsToAdd: credits,
      );
      // Restored owned items are also consumables. Consume after the local
      // ledger commits so they cannot be re-granted on every app launch.
      try {
        final consumed = await CafeBazaarBilling.consume(purchase.purchaseToken);
        if (!consumed) {
          debugPrint('[BazaarBilling] مصرف خرید بازیابی‌شده انجام نشد.');
        }
      } catch (e) {
        debugPrint('[BazaarBilling] مصرف خرید بازیابی‌شده خطا داد: $e');
      }
    }
  }

  int? _productCredits(String productId) => switch (productId) {
        'credit_10' => 10,
        'credit_35' => 25,
        'credit_90' => 60,
        _ => null,
      };

  Future<void> disconnect() async {
    if (!_connected) return;
    await CafeBazaarBilling.disconnect();
    _connected = false;
  }
}

class BazaarBillingException implements Exception {
  const BazaarBillingException(this.message);
  final String message;

  @override
  String toString() => message;
}
