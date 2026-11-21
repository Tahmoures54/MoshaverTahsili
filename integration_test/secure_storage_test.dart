import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:moshaver_tahsili/education/education_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Android Keystore encrypts, authenticates and reopens local study data',
    // NOTE: WidgetTester is intentionally unused. IntegrationTestWidgetsFlutterBinding
    // is required for real platform-channel access (Android Keystore, SharedPreferences).
    (_) async {
      // ⚠️ DESTRUCTIVE: This test clears ALL app-shared-preferences on disk.
      // Run only on a disposable emulator/CI runner — never on a personal device.
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      try {
        // === 1. Write sensitive data through the real platform-backed store ===
        final store = await EducationStore.open(preferences: prefs);
        await store.saveProfile({'nickname': 'keystore-private-profile'});
        await store.addTask({
          'id': 'secure-task',
          'title': 'keystore-private-task',
        });
        await store.grantProduct(
          productId: 'credit_10',
          purchaseToken: 'keystore-private-purchase-token',
          creditsToAdd: 100,
        );

        // === 2. At-rest values must be encrypted with a non-trivial body ===
        final encryptedProfile = prefs.getString('edu.profile');
        final encryptedTasks = prefs.getString('edu.tasks');
        final encryptedWallet = prefs.getString(EducationStore.walletKey);
        expect(encryptedProfile, isNotNull);
        expect(encryptedTasks, isNotNull);
        expect(encryptedWallet, isNotNull);

        for (final blob in [
          encryptedProfile!,
          encryptedTasks!,
          encryptedWallet!,
        ]) {
          expect(blob, startsWith(EducationStore.encryptedPrefix));
          final body = blob.substring(EducationStore.encryptedPrefix.length);
          expect(
            body.length,
            greaterThan(32),
            reason: 'Ciphertext body must be non-trivial (≥ 32 chars)',
          );
        }

        // === 3. No plaintext may leak into SharedPreferences ===
        expect(encryptedProfile, isNot(contains('keystore-private-profile')));
        expect(encryptedTasks, isNot(contains('keystore-private-task')));
        expect(encryptedWallet, isNot(contains('keystore-private-purchase-token')));
        expect(encryptedWallet, isNot(contains('"credits"')));

        // === 4. Reopen on the same platform keystore must round-trip ===
        final reopened = await EducationStore.open(preferences: prefs);
        expect(reopened.profile?['nickname'], 'keystore-private-profile');
        expect(reopened.tasks.single['title'], 'keystore-private-task');
        expect(
          reopened.credits,
          105,
          reason: 'welcome credits (5) + granted credits (100)',
        );
        expect(
          reopened.creditHistory.any(
            (entry) => entry['id'] == 'welcome-credits-v1',
          ),
          isTrue,
        );
      } finally {
        // Keep the emulator clean for the next integration test / rebuild.
        // (No-op on CI ephemeral runners, but essential on a real device.)
        await prefs.clear();
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
