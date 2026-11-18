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

  test('new wallet receives five welcome credits once and charges one per successful answer', () async {
    final store = await EducationStore.open();
    expect(store.credits, 5);
    expect(store.freeAiUsesRemaining, 0);
    final welcome = store.creditHistory.single;
    expect(welcome['kind'], 'bonus');
    expect(welcome['amount'], 5);
    final untouchedReopen = await EducationStore.open(preferences: store.prefs);
    expect(untouchedReopen.credits, 5);
    expect(untouchedReopen.creditHistory.where((entry) => entry['kind'] == 'bonus'), hasLength(1));

    final reservation = await store.prepareAiRequest(id: 'first', question: 'پرسش اول');
    expect(reservation.usesFreeUse, isFalse);
    expect(store.credits, 4);
    await store.completeAiRequest('first', 'پاسخ معتبر');
    await store.refundAiRequest('first');
    expect(store.credits, 4);
    final reopened = await EducationStore.open(preferences: store.prefs);
    expect(reopened.credits, 4);
    expect(reopened.creditHistory.where((entry) => entry['kind'] == 'bonus'), hasLength(1));
  });

  test('legacy wallets keep their exact balance and do not receive a retroactive welcome grant', () async {
    SharedPreferences.setMockInitialValues({
      EducationStore.walletKey: '{"version":2,"credits":7,"successful_uses":2}',
    });
    final store = await EducationStore.open();
    expect(store.credits, 7);
    expect(store.creditHistory.where((entry) => entry['kind'] == 'bonus'), isEmpty);
  });
}
