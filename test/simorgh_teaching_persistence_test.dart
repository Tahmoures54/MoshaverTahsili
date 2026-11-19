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

  test('persists and restores an active teaching session', () async {
    final store = await EducationStore.open();
    await store.saveTeachingSessions([
      {
        'id': 'simorgh-teaching-active',
        'active': true,
        'topic': 'معادله درجه دوم',
        'grade': 'متوسطه دوم · دهم',
        'stage': 'guidedPractice',
        'diagnosticCount': 3,
        'diagnosticCorrect': 2,
      },
    ]);

    final reopened = await EducationStore.open(preferences: store.prefs);
    expect(reopened.teachingSessions, hasLength(1));
    expect(reopened.teachingSessions.single['topic'], 'معادله درجه دوم');
    expect(reopened.teachingSessions.single['stage'], 'guidedPractice');
    expect(reopened.teachingSessions.single['active'], isTrue);
  });
}
