import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moshaver_tahsili/education_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows Persian welcome and privacy notice', (tester) async {
    await tester.pumpWidget(const EducationApp());
    await tester.pumpAndSettle();

    expect(find.text('مشاور هوشمند تحصیلی'), findsOneWidget);
    expect(find.text('سخنی با اولیا و دانش‌آموزان گرامی'), findsOneWidget);
    expect(find.text('بزن بریم'), findsOneWidget);
  });

  testWidgets('study skills guide contains practical learning methods', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: StudyTipsPage()));
    await tester.pumpAndSettle();

    expect(find.text('روش‌های مؤثر مطالعه'), findsOneWidget);
    expect(find.text('مطالعه فعال'), findsOneWidget);
    expect(find.text('مرور فاصله‌دار'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('آمادگی برای امتحان'), 350, scrollable: find.byType(Scrollable).first);
    expect(find.text('آمادگی برای امتحان'), findsOneWidget);
  });
}
