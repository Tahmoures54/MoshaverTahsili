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

  test('keeps the newest 80 advisor messages', () async {
    final store = await EducationStore.open();
    final messages = List.generate(
      85,
      (index) => {'role': 'user', 'content': 'message-$index'},
    );

    await store.saveMessages(messages);

    expect(store.messages, hasLength(80));
    expect(store.messages.first['content'], 'message-5');
    expect(store.messages.last['content'], 'message-84');
  });

  test('grants a purchased credit pack only once per Bazaar purchase token', () async {
    final store = await EducationStore.open();
    final first = await store.grantProduct(
      productId: 'credit_10',
      purchaseToken: 'bazaar-token-1',
      creditsToAdd: 10,
    );
    final duplicate = await store.grantProduct(
      productId: 'credit_10',
      purchaseToken: 'bazaar-token-1',
      creditsToAdd: 10,
    );

    expect(first, isTrue);
    expect(duplicate, isFalse);
    expect(store.credits, 10);
  });

  test('allows two successful AI uses for free then consumes one credit per success', () async {
    final store = await EducationStore.open();
    expect(store.freeAiUsesRemaining, 2);
    expect(store.canUseAi, isTrue);

    expect(await store.recordSuccessfulAiUse(), isTrue);
    expect(await store.recordSuccessfulAiUse(), isTrue);
    expect(store.freeAiUsesRemaining, 0);
    expect(store.canUseAi, isFalse);

    await store.grantProduct(
      productId: 'credit_10',
      purchaseToken: 'bazaar-token-2',
      creditsToAdd: 10,
    );
    expect(await store.recordSuccessfulAiUse(), isTrue);
    expect(store.credits, 9);
  });

  test('keeps purchased credits and free-trial usage when student workspace is cleared', () async {
    final store = await EducationStore.open();
    await store.grantProduct(
      productId: 'credit_10',
      purchaseToken: 'bazaar-token-3',
      creditsToAdd: 10,
    );
    await store.recordSuccessfulAiUse();
    await store.saveProfile({'grade': 'متوسطه اول'});
    await store.clear();

    expect(store.profile, isNull);
    expect(store.credits, 10);
    expect(store.freeAiUsesRemaining, 1);
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
