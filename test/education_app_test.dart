import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:moshaver_tahsili/education_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() { SharedPreferences.setMockInitialValues({}); });
  testWidgets('shows Persian welcome and privacy notice', (tester) async {
    await tester.pumpWidget(const EducationApp());
    await tester.pumpAndSettle();
    expect(find.text('مشاور هوشمند تحصیلی'), findsOneWidget);
    expect(find.text('سخنی با اولیا و دانش‌آموزان گرامی'), findsOneWidget);
    expect(find.text('بزن بریم'), findsOneWidget);
  });
}
