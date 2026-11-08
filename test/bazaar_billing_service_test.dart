import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moshaver_tahsili/education/bazaar_billing_service.dart';
import 'package:moshaver_tahsili/education/education_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

VerifiedPurchase verifiedPurchase({String id = 'credit_10', String token = 'verified-token',
  String package = BazaarBillingService.packageName, String signature = 'verified-by-sdk', bool purchased = true}) =>
    VerifiedPurchase(productId: id, purchaseToken: token, packageName: package, signature: signature, purchased: purchased);

class FakeGateway implements BazaarGateway {
  FakeGateway({this.consumeSucceeds = true, this.connectFails = false});
  bool consumeSucceeds, connectFails;
  int connects = 0, purchases = 0, consumes = 0, disconnects = 0;
  VerifiedPurchase next = verifiedPurchase();
  List<VerifiedPurchase> inventory = [];
  PlatformException? purchaseError;
  Completer<void>? purchaseGate;

  @override
  Future<void> connect(String publicKey, {required void Function() onDisconnected}) async {
    connects++;
    if (connectFails) throw PlatformException(code: 'PAYMENT_CONNECTION_IS_NOT_CONNECTED', message: 'sensitive platform detail');
  }
  @override
  Future<VerifiedPurchase> purchase(String productId) async {
    purchases++;
    if (purchaseGate != null) await purchaseGate!.future;
    if (purchaseError != null) throw purchaseError!;
    return next;
  }
  @override
  Future<List<VerifiedPurchase>> purchasedProducts() async => inventory;
  @override
  Future<List<ShopProduct>> products(List<String> ids) async =>
      CreditCatalog.products.map((product) => ShopProduct(product, 'قیمت آزمایشی بازار')).toList();
  @override
  Future<bool> consume(String token) async { consumes++; return consumeSucceeds; }
  @override
  Future<void> disconnect() async { disconnects++; }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<(EducationStore, FakeGateway, BazaarBillingService)> setup({bool consume = true}) async {
    final store = await EducationStore.open();
    final gateway = FakeGateway(consumeSucceeds: consume);
    return (store, gateway, BazaarBillingService(store, gateway: gateway,
        publicKey: 'test-public-key', catalogConfirmed: true, supportedPlatform: true));
  }

  test('missing key or unconfirmed catalog never connects or purchases', () async {
    final store = await EducationStore.open();
    final gateway = FakeGateway();
    final service = BazaarBillingService(store, gateway: gateway, publicKey: '', catalogConfirmed: true, supportedPlatform: true);
    await expectLater(service.buy('credit_10'), throwsA(isA<BillingException>()));
    expect(gateway.connects, 0);
    expect(gateway.purchases, 0);
    final unconfirmed = BazaarBillingService(store, gateway: gateway, publicKey: 'key', catalogConfirmed: false, supportedPlatform: true);
    expect(unconfirmed.isConfigured, isFalse);
    expect(unconfirmed.configurationMessage, contains('تأیید نشده'));
  });

  test('valid purchase persists balance before consumption', () async {
    final (store, gateway, service) = await setup();
    final result = await service.buy('credit_10');
    expect(result.credited, 1);
    expect(result.consumptionPending, isFalse);
    expect(store.credits, 10);
    expect(store.creditHistory.single['kind'], 'purchase');
    expect(gateway.consumes, 1);
    expect(EducationStore(store.prefs).credits, 10);
  });

  test('failed consumption keeps credit; restore retries without double credit', () async {
    final (store, gateway, service) = await setup(consume: false);
    expect((await service.buy('credit_10')).consumptionPending, isTrue);
    expect(store.credits, 10);
    gateway.inventory = [verifiedPurchase()];
    final first = await service.restorePurchases();
    expect(first.alreadyCredited, 1);
    expect(first.consumptionPending, isTrue);
    gateway.consumeSucceeds = true;
    final second = await service.restorePurchases();
    expect(second.credited, 0);
    expect(second.consumptionPending, isFalse);
    expect(store.credits, 10);
    expect(gateway.consumes, 3);
  });

  test('duplicate direct delivery is not credited twice', () async {
    final (store, gateway, service) = await setup();
    expect((await service.buy('credit_10')).credited, 1);
    expect((await service.buy('credit_10')).alreadyCredited, 1);
    expect(store.credits, 10);
    expect(gateway.consumes, 2);
  });

  test('rejects wrong package, product, signature, token and purchase state', () async {
    final (store, gateway, service) = await setup();
    for (final invalid in [verifiedPurchase(package: 'other.app'), verifiedPurchase(id: 'credit_35'),
      verifiedPurchase(signature: ''), verifiedPurchase(token: ''), verifiedPurchase(purchased: false)]) {
      gateway.next = invalid;
      await expectLater(service.buy('credit_10'), throwsA(isA<BillingException>()));
    }
    expect(store.credits, 0);
    expect(gateway.consumes, 0);
  });

  test('restore skips invalid/unknown products and reports no false success', () async {
    final (store, gateway, service) = await setup();
    gateway.inventory = [verifiedPurchase(id: 'unknown'), verifiedPurchase(package: 'other.app'), verifiedPurchase(signature: '')];
    final result = await service.restorePurchases();
    expect(result.skipped, 3);
    expect(result.credited, 0);
    expect(result.message, contains('اعتباری اضافه نشد'));
    expect(store.credits, 0);
    expect(gateway.consumes, 0);
  });

  test('restore credits multiple distinct valid tokens atomically', () async {
    final (store, gateway, service) = await setup();
    gateway.inventory = [verifiedPurchase(token: 'a'), verifiedPurchase(id: 'credit_35', token: 'b'), verifiedPurchase(token: 'a')];
    final result = await service.restorePurchases();
    expect(result.credited, 2);
    expect(result.alreadyCredited, 1);
    expect(store.credits, 35);
  });

  test('cancellation and connection errors are sanitized; no credit changes', () async {
    final (store, gateway, service) = await setup();
    gateway.purchaseError = PlatformException(code: 'PURCHASE_CANCELLED', message: 'raw platform data');
    await expectLater(service.buy('credit_10'), throwsA(isA<BillingException>()
        .having((e) => e.cancelled, 'cancelled', isTrue).having((e) => e.message, 'safe', isNot(contains('raw platform')))));
    gateway.connectFails = true;
    await expectLater(service.restorePurchases(), throwsA(isA<BillingException>().having((e) => e.message, 'safe', isNot(contains('sensitive')))));
    expect(store.credits, 0);
  });

  test('overlapping purchase operations are rejected', () async {
    final (store, gateway, service) = await setup();
    gateway.purchaseGate = Completer<void>();
    final first = service.buy('credit_10');
    await Future<void>.delayed(Duration.zero);
    await expectLater(service.buy('credit_35'), throwsA(isA<BillingException>()));
    gateway.purchaseGate!.complete();
    await first;
    expect(gateway.purchases, 1);
    expect(store.credits, 10);
  });

  test('loads real gateway prices without hardcoded monetary amounts', () async {
    final (_, _, service) = await setup();
    final products = await service.loadProducts();
    expect(products, hasLength(3));
    expect(products.every((product) => product.price == 'قیمت آزمایشی بازار'), isTrue);
  });
}
