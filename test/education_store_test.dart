import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moshaver_tahsili/education/education_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() { SharedPreferences.setMockInitialValues({}); });

  test('stores student profile, study tasks, exams and flashcards locally', () async {
    final store = await EducationStore.open();
    await store.saveProfile({'grade': 'متوسطه دوم', 'field': 'ریاضی', 'nickname': 'آزمون'});
    await store.addTask({'id': 'task-1', 'title': 'حل تمرین', 'subject': 'ریاضی', 'minutes': 45, 'done': false});
    await store.addExam({'id': 'exam-1', 'subject': 'فیزیک', 'score': 17, 'max': 20});
    await store.addCard({'id': 'card-1', 'q': 'شتاب چیست؟', 'a': 'نرخ تغییر سرعت', 'interval': 0});

    expect(store.profile?['grade'], 'متوسطه دوم');
    expect(store.tasks.single['title'], 'حل تمرین');
    expect(store.exams.single['score'], 17);
    expect(store.cards.single['q'], 'شتاب چیست؟');

    await store.toggleTask('task-1');
    expect(store.tasks.single['done'], isTrue);
  });

  test('clear removes the complete local student workspace', () async {
    final store = await EducationStore.open();
    await store.saveProfile({'grade': 'ابتدایی'});
    await store.addTask({'id': 'task-1', 'title': 'خواندن', 'subject': 'فارسی', 'minutes': 20, 'done': false});
    await store.saveMessages([{'role': 'user', 'content': 'سلام'}]);
    await store.clear();

    expect(store.profile, isNull);
    expect(store.tasks, isEmpty);
    expect(store.messages, isEmpty);
  });
}
