import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moshaver_tahsili/education/referral_page.dart';

void main() {
  testWidgets('referral page displays the official Bazaar link and sharing copy',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ReferralPage()));

    expect(find.text('معرفی سیمرغ به دوستان'), findsOneWidget);
    expect(find.text(simorghBazaarUrl), findsOneWidget);
    expect(find.textContaining('سیمرغ؛ مشاور هوشمند تحصیلی'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('معرفی به دوستان'), 250, scrollable: find.byType(Scrollable).first);
    expect(find.text('معرفی به دوستان'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('کپی متن و لینک'), 250, scrollable: find.byType(Scrollable).first);
    expect(find.text('کپی متن و لینک'), findsOneWidget);
  });

  testWidgets('copy action confirms that the referral text was copied',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ReferralPage()));
    await tester.scrollUntilVisible(find.text('کپی متن و لینک'), 250, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('کپی متن و لینک'));
    await tester.pumpAndSettle();

    final clipboard = await Clipboard.getData('text/plain');
    expect(clipboard?.text, simorghReferralMessage);
  });
}
