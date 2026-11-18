import 'package:flutter_test/flutter_test.dart';
import 'package:moshaver_tahsili/education/education_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/memory_secure_local_cipher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EducationStore.secureCipherOverride = MemorySecureLocalCipher();
  });

  test('migrates existing profile, study tasks and wallet to encrypted preferences', () async {
    SharedPreferences.setMockInitialValues({
      'edu.profile': '{"nickname":"student-private","grade":"دهم"}',
      'edu.tasks': '[{"id":"t1","title":"private study task"}]',
      EducationStore.walletKey: '{"credits":7,"successful_uses":2,"purchase_tokens":[]}',
    });
    final store = await EducationStore.open();
    final profileCiphertext = store.prefs.getString('edu.profile')!;
    final tasksCiphertext = store.prefs.getString('edu.tasks')!;
    final walletCiphertext = store.prefs.getString(EducationStore.walletKey)!;
    expect(profileCiphertext, startsWith(EducationStore.encryptedPrefix));
    expect(tasksCiphertext, startsWith(EducationStore.encryptedPrefix));
    expect(walletCiphertext, startsWith(EducationStore.encryptedPrefix));
    expect(profileCiphertext, isNot(contains('student-private')));
    expect(tasksCiphertext, isNot(contains('private study task')));
    expect(walletCiphertext, isNot(contains('"credits"')));
    expect(store.profile?['nickname'], 'student-private');
    expect(store.tasks.single['title'], 'private study task');
    expect(store.credits, 7);
    final reopened = await EducationStore.open(preferences: store.prefs);
    expect(reopened.profile?['nickname'], 'student-private');
    expect(reopened.tasks.single['title'], 'private study task');
    expect(reopened.credits, 7);
  });

  test('refuses tampered ciphertext without replacing the stored value', () async {
    SharedPreferences.setMockInitialValues({'edu.profile': 'enc:v1:not-valid-base64!'});
    final prefs = await SharedPreferences.getInstance();
    final before = prefs.getString('edu.profile');
    await expectLater(EducationStore.open(preferences: prefs), throwsA(isA<LocalDataException>()));
    expect(prefs.getString('edu.profile'), before);
  });

  test('new writes and AI ledger updates are encrypted at rest', () async {
    final store = await EducationStore.open();
    await store.saveProfile({'nickname': 'secret-name'});
    await store.addTask({'id': 't2', 'title': 'secret-title'});
    await store.grantProduct(productId: 'credit_10', purchaseToken: 'purchase-secret', creditsToAdd: 10);
    expect(store.prefs.getString('edu.profile'), startsWith(EducationStore.encryptedPrefix));
    expect(store.prefs.getString('edu.tasks'), startsWith(EducationStore.encryptedPrefix));
    final wallet = store.prefs.getString(EducationStore.walletKey)!;
    expect(wallet, startsWith(EducationStore.encryptedPrefix));
    expect(wallet, isNot(contains('purchase-secret')));
    expect(store.walletSnapshot['credits'], 10);
  });
}
