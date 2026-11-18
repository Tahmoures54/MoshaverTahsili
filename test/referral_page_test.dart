import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moshaver_tahsili/education/referral_page.dart';

void main() {
  testWidgets('referral page displays the official Bazaar link and sharing copy',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ReferralPage()));

    expect(find.text('معرفی سیمرغ به دوستان'), findsOneWidget);
    expect(find.text(simorghBazaarUrl), findsOneWidget);
    expect(find.textContaining('سیمرغ؛ مشاور هوشمند تحصیلی'), findsOneWidget);
    await tester.ensureVisible(find.text('معرفی به دوستان'));
    expect(find.text('معرفی به دوستان'), findsOneWidget);
    await tester.ensureVisible(find.text('کپی متن و لینک'));
    expect(find.text('کپی متن و لینک'), findsOneWidget);
  });

  testWidgets('copy action confirms that the referral text was copied',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ReferralPage()));
    await tester.ensureVisible(find.text('کپی متن و لینک'));
    await tester.tap(find.text('کپی متن و لینک'));
    await tester.pump();

    expect(find.text('متن معرفی و لینک کپی شد.'), findsOneWidget);
  });
}
