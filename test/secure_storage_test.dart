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

  test(
    'migrates existing profile, study tasks and wallet to encrypted preferences',
    () async {
      SharedPreferences.setMockInitialValues({
        'edu.profile': '{"nickname":"student-private","grade":"دهم"}',
        'edu.tasks': '[{"id":"t1","title":"private study task"}]',
        EducationStore.walletKey:
            '{"credits":7,"successful_uses":2,"purchase_tokens":[]}',
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
    },
  );

  test(
    'keeps other workspace sections usable when one ciphertext is damaged',
    () async {
      SharedPreferences.setMockInitialValues({
        'edu.profile': 'enc:v2:not-valid-base64!',
        'edu.tasks': '[{"id":"safe-task","title":"قابل استفاده","done":false}]',
      });
      final prefs = await SharedPreferences.getInstance();
      final before = prefs.getString('edu.profile');
      final store = await EducationStore.open(preferences: prefs);
      expect(store.dataError('edu.profile'), isNotNull);
      expect(store.profile, isNull);
      expect(store.tasks.single['id'], 'safe-task');
      expect(prefs.getString('edu.profile'), before);
      await expectLater(
        store.saveProfile({'grade': 'دهم'}),
        throwsA(isA<LocalDataException>()),
      );
      await expectLater(
        store.exportBackup(),
        throwsA(isA<LocalDataException>()),
      );
    },
  );

  test(
    'keeps a damaged wallet unavailable without blocking local learning',
    () async {
      SharedPreferences.setMockInitialValues({
        EducationStore.walletKey: 'enc:v2:not-valid-base64!',
        'edu.tasks': '[{"id":"offline","title":"مرور درس","done":false}]',
      });
      final prefs = await SharedPreferences.getInstance();
      final before = prefs.getString(EducationStore.walletKey);
      final store = await EducationStore.open(preferences: prefs);
      expect(store.walletError, isNotNull);
      expect(store.canUseAi, isFalse);
      expect(store.tasks.single['id'], 'offline');
      expect(prefs.getString(EducationStore.walletKey), before);
      await expectLater(
        store.prepareAiRequest(id: 'blocked', question: 'q'),
        throwsA(isA<LocalDataException>()),
      );
    },
  );

  test('new writes and AI ledger updates are encrypted at rest', () async {
    final store = await EducationStore.open();
    await store.saveProfile({'nickname': 'secret-name'});
    await store.addTask({'id': 't2', 'title': 'secret-title'});
    await store.grantProduct(
      productId: 'credit_10',
      purchaseToken: 'purchase-secret',
      creditsToAdd: 100,
    );
    expect(
      store.prefs.getString('edu.profile'),
      startsWith(EducationStore.encryptedPrefix),
    );
    expect(
      store.prefs.getString('edu.tasks'),
      startsWith(EducationStore.encryptedPrefix),
    );
    final wallet = store.prefs.getString(EducationStore.walletKey)!;
    expect(wallet, startsWith(EducationStore.encryptedPrefix));
    expect(wallet, isNot(contains('purchase-secret')));
    expect(store.walletSnapshot['credits'], 105);
  });
  test(
    'preserves a damaged encrypted career draft instead of silently replacing it',
    () async {
      SharedPreferences.setMockInitialValues({'edu.career.draft': '{broken'});
      final store = await EducationStore.open();
      expect(store.careerDraft, isNull);
      expect(store.dataError('edu.career.draft'), isNotNull);
      await expectLater(
        store.saveCareerDraft({'goal': 'new'}),
        throwsA(isA<LocalDataException>()),
      );
      expect(
        store.prefs.getString('edu.career.draft'),
        startsWith(EducationStore.encryptedPrefix),
      );
    },
  );
}
