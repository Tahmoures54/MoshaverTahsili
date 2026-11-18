import 'package:flutter_test/flutter_test.dart';
import 'package:moshaver_tahsili/education/education_store.dart';
import 'support/memory_secure_local_cipher.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EducationStore.secureCipherOverride = MemorySecureLocalCipher();
  });

  test('free advisor answers are recorded as free, not as credit deductions', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await EducationStore.open();

    for (final id in List.generate(5, (index) => 'free-${index + 1}')) {
      final reservation = await store.prepareAiRequest(id: id, question: 'پرسش رایگان');
      expect(reservation.usesFreeUse, isTrue);
      await store.completeAiRequest(id, 'پاسخ رایگان');
    }

    expect(store.successfulAiUses, 5);
    expect(store.credits, 0);
    expect(store.creditHistory.where((entry) => entry['kind'] == 'ai')
        .map((entry) => entry['amount']), everyElement(0));

    await store.grantProduct(productId: 'credit_10',
        purchaseToken: 'paid-token', creditsToAdd: 100);
    final paid = await store.prepareAiRequest(id: 'paid-1', question: 'پرسش پولی');
    expect(paid.usesFreeUse, isFalse);
    await store.completeAiRequest('paid-1', 'پاسخ پولی');

    final aiAmounts = store.creditHistory
        .where((entry) => entry['kind'] == 'ai')
        .map((entry) => entry['amount']).toList();
    expect(aiAmounts, [1, 0, 0, 0, 0, 0]);
    expect(store.credits, 99);
  });
}
