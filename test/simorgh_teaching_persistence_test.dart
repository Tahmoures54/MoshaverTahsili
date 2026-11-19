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
        'id': 'simorgh-teaching-archived',
        'active': false,
        'topic': 'کسرها',
        'grade': 'هفتم',
        'stage': 'completed',
        'diagnosticCount': 3,
        'diagnosticCorrect': 1,
        'practiceAttempts': 2,
        'masteryCount': 3,
        'masteryCorrect': 2,
        'reteachCount': 1,
        'explanationVariant': 2,
        'lastError': 'procedural',
      },
      {
        'id': 'simorgh-teaching-active',
        'active': true,
        'topic': 'معادله درجه دوم',
        'grade': 'متوسطه دوم · دهم',
        'stage': 'masteryCheck',
        'diagnosticCount': 3,
        'diagnosticCorrect': 1,
        'practiceAttempts': 2,
        'masteryCount': 1,
        'masteryCorrect': 1,
        'reteachCount': 1,
        'explanationVariant': 2,
        'lastError': null,
      },
    ]);

    final reopened = await EducationStore.open(preferences: store.prefs);
    expect(reopened.teachingSessions, hasLength(2));
    final active = reopened.teachingSessions.last;
    expect(active['id'], 'simorgh-teaching-active');
    expect(active['topic'], 'معادله درجه دوم');
    expect(active['grade'], 'متوسطه دوم · دهم');
    expect(active['stage'], 'masteryCheck');
    expect(active['diagnosticCount'], 3);
    expect(active['diagnosticCorrect'], 1);
    expect(active['practiceAttempts'], 2);
    expect(active['masteryCount'], 1);
    expect(active['masteryCorrect'], 1);
    expect(active['reteachCount'], 1);
    expect(active['explanationVariant'], 2);
    expect(active['active'], isTrue);
    expect(reopened.teachingSessions.first['active'], isFalse);
    expect(reopened.teachingSessions.first['stage'], 'completed');
  });
}
