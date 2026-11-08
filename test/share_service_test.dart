import 'package:flutter_test/flutter_test.dart';

import 'package:smart_mechanic/services/share_service.dart';

void main() {
  group('ShareService — متن‌های دعوت', () {
    test('لینک دانلود رسمی کافه‌بازار تنظیم شده است', () {
      expect(
        ShareService.downloadUrl,
        'https://cafebazaar.ir/app/ir.smartmec.app',
      );
    });

    test('اشتراک پاسخ شامل لینک رسمی کافه‌بازار است', () {
      final text = ShareService.responseShare(result: 'پاسخ آزمایشی');
      expect(text, contains('https://cafebazaar.ir/app/ir.smartmec.app'));
      expect(text, contains('دریافت نسخه اندروید از کافه‌بازار'));
    });

    test('supportInvite بدون کد معرف، لینک دریافت نسخه دارد', () {
      final text = ShareService.supportInvite();
      expect(text, contains(ShareService.downloadUrl));
      expect(text, isNot(contains('کد معرف')));
    });

    test('supportInvite با کد معرف، کد را نشان می‌دهد', () {
      final text = ShareService.supportInvite(referralCode: 'ABCD12');
      expect(text, contains(ShareService.downloadUrl));
      expect(text, contains('ABCD12'));
      expect(text, contains('کد معرف'));
    });

    test('appPitch با کد معرف، کد را نشان می‌دهد', () {
      final text = ShareService.appPitch(referralCode: 'XY99');
      expect(text, contains('XY99'));
      expect(text, contains(ShareService.downloadUrl));
    });

    test('diagnosisShare نام و سال خودرو را در سرصفحه می‌آورد', () {
      final text = ShareService.diagnosisShare(
        result: 'خلاصهٔ تشخیص',
        carName: 'پژو ۲۰۶',
        year: '۱۴۰۲',
      );
      expect(text, contains('پژو ۲۰۶'));
      expect(text, contains('مدل ۱۴۰۲'));
      expect(text, contains('خلاصهٔ تشخیص'));
      expect(text, contains(ShareService.downloadUrl));
    });

    test('diagnosisShare با متن خالی هم کرش نمی‌کند', () {
      final text = ShareService.diagnosisShare(result: '');
      expect(text, isNotEmpty);
      expect(text, contains(ShareService.downloadUrl));
    });
  });
}
