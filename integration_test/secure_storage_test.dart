import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:moshaver_tahsili/education/education_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android Keystore encrypts, authenticates and reopens local study data', (_) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    final store = await EducationStore.open(preferences: prefs);
    await store.saveProfile({'nickname': 'keystore-private-profile'});
    await store.addTask({'id': 'secure-task', 'title': 'keystore-private-task'});
    await store.grantProduct(
      productId: 'credit_10',
      purchaseToken: 'keystore-private-purchase-token',
      creditsToAdd: 10,
    );

    final encryptedProfile = prefs.getString('edu.profile')!;
    final encryptedTasks = prefs.getString('edu.tasks')!;
    final encryptedWallet = prefs.getString(EducationStore.walletKey)!;
    expect(encryptedProfile, startsWith(EducationStore.encryptedPrefix));
    expect(encryptedTasks, startsWith(EducationStore.encryptedPrefix));
    expect(encryptedWallet, startsWith(EducationStore.encryptedPrefix));
    expect(encryptedProfile, isNot(contains('keystore-private-profile')));
    expect(encryptedTasks, isNot(contains('keystore-private-task')));
    expect(encryptedWallet, isNot(contains('keystore-private-purchase-token')));

    final reopened = await EducationStore.open(preferences: prefs);
    expect(reopened.profile?['nickname'], 'keystore-private-profile');
    expect(reopened.tasks.single['title'], 'keystore-private-task');
    expect(reopened.credits, 10);
  });
}
