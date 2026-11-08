import 'package:cafebazaar_billing/cafebazaar_billing.dart';
import 'package:flutter/foundation.dart';
import 'education_store.dart';

class BazaarBillingService {
  BazaarBillingService(this.store);
  final EducationStore store;
  static const String _publicKey = String.fromEnvironment('BAZAAR_RSA_PUBLIC_KEY');
  bool _connected = false;
  bool get isConfigured => _publicKey.trim().isNotEmpty;

  Future<void> connect() async {
    if (_connected) return;
    if (!isConfigured) throw const BazaarBillingException('کلید عمومی پرداخت بازار در نسخه برنامه تنظیم نشده است.');
    await CafeBazaarBilling.connect(_publicKey);
    _connected = true;
  }

  Future<void> buy(String productId) async {
    final credits = _productCredits(productId);
    if (credits == null) throw BazaarBillingException('بسته اعتبار ناشناخته است: $productId');
    await connect();
    final purchase = await CafeBazaarBilling.purchase(productId);
    if (purchase.purchaseState != PurchaseState.PURCHASED ||
        purchase.productId != productId || purchase.purchaseToken.trim().isEmpty) {
      throw const BazaarBillingException('خرید توسط بازار تأیید نشد؛ اعتباری اضافه نشد.');
    }
    await store.grantProduct(productId: productId, purchaseToken: purchase.purchaseToken, creditsToAdd: credits);
    try {
      final consumed = await CafeBazaarBilling.consume(purchase.purchaseToken);
      if (!consumed) debugPrint('[BazaarBilling] توکن بازار مصرف نشد؛ خرید محلی ثبت شد.');
    } catch (error) {
      debugPrint('[BazaarBilling] خطا در مصرف توکن بازار: $error');
    }
  }

  Future<void> restorePurchases() async {
    await connect();
    final purchases = await CafeBazaarBilling.getAllPurchasedProducts();
    for (final purchase in purchases) {
      if (purchase.purchaseState != PurchaseState.PURCHASED || purchase.purchaseToken.trim().isEmpty) continue;
      final credits = _productCredits(purchase.productId);
      if (credits == null) continue;
      await store.grantProduct(productId: purchase.productId, purchaseToken: purchase.purchaseToken, creditsToAdd: credits);
      try { await CafeBazaarBilling.consume(purchase.purchaseToken); }
      catch (error) { debugPrint('[BazaarBilling] خطا در مصرف خرید بازیابی‌شده: $error'); }
    }
  }

  int? _productCredits(String id) => switch (id) {
    'credit_10' => 10, 'credit_35' => 25, 'credit_90' => 60, _ => null,
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
