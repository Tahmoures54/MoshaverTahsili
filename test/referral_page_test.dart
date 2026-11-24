import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moshaver_tahsili/education/referral_page.dart';

void main() {
  testWidgets(
    'referral page displays the official Bazaar link and sharing copy',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ReferralPage()));

      expect(find.text('معرفی سیمرغ به دوستان'), findsOneWidget);
      expect(find.text(simorghBazaarUrl), findsOneWidget);
      expect(find.textContaining('سیمرغ؛ مشاور هوشمند تحصیلی'), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, -520));
      await tester.pumpAndSettle();
      expect(find.text('معرفی به دوستان'), findsOneWidget);
      await tester.drag(find.byType(ListView).first, const Offset(0, -420));
      await tester.pumpAndSettle();
      expect(find.text('کپی متن و لینک'), findsOneWidget);
    },
  );

  // Verify the platform payload without depending on the host clipboard.
  testWidgets(
    'copy action writes the complete referral message to the clipboard',
    (tester) async {
      final clipboardCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboardCalls.add(call);
            }
            return null;
          });

      await tester.pumpWidget(const MaterialApp(home: ReferralPage()));
      await tester.ensureVisible(find.text('کپی متن و لینک'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('کپی متن و لینک'));
      await tester.pump();

      expect(clipboardCalls, hasLength(1));
      expect(
        (clipboardCalls.single.arguments as Map)['text'],
        simorghReferralMessage,
      );
    },
  );
}
