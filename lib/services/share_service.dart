import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants.dart';

/// متن‌ها و اکشن‌های اشتراک‌گذاری — یک منبع برای کل اپ
class ShareService {
  ShareService._();

  /// صفحهٔ رسمی دانلود برنامه از کافه‌بازار.
  static const String downloadUrl =
      'https://cafebazaar.ir/app/ir.smartmec.app';
  static const String appName = 'مکانیک هوشمند';

  static String appPitch({String? referralCode}) {
    final referral = (referralCode != null && referralCode.isNotEmpty)
        ? '\n\nبا کد معرف من ثبت‌نام کن و اعتبار هدیه بگیر:\n🎁 $referralCode'
        : '';
    return '🚗 $appName — عیب‌یابی ماشین با هوش مصنوعی\n\n'
        'قبل از رفتن به تعمیرگاه، در چند ثانیه علت احتمالی مشکل را می‌فهمی؛ '
        'هم خیالت راحت‌تر می‌شود، هم کمتر هزینه الکی می‌دهی.\n'
        '$referral\n\n'
        '📲 دریافت نسخه اندروید از کافه‌بازار:\n$downloadUrl';
  }

  static String diagnosisShare({
    required String result,
    String? carName,
    String? year,
    String? referralCode,
  }) {
    final carLine = [
      if (carName != null && carName.isNotEmpty) carName,
      if (year != null && year.isNotEmpty) 'مدل $year',
    ].join(' · ');

    final header = carLine.isEmpty
        ? '🔧 نتیجه عیب‌یابی من با $appName:\n\n'
        : '🔧 نتیجه عیب‌یابی $carLine با $appName:\n\n';

    final referral = (referralCode != null && referralCode.isNotEmpty)
        ? '\n\nبا کد معرف $referralCode در $appName ثبت‌نام کن و اعتبار هدیه بگیر.'
        : '';
    final download = '\n\n📲 دریافت نسخه اندروید از کافه‌بازار:\n$downloadUrl';

    return '$header$result$referral$download';
  }

  /// متن آماده برای وضعیت ۲۴ساعته واتساپ
  static String whatsappStatus({String? referralCode}) {
    final referral = (referralCode != null && referralCode.isNotEmpty)
        ? '\nکد معرف من: $referralCode'
        : '';
    return 'از وقتی «$appName» دارم، دیگه چشم‌بسته نمی‌رم تعمیرگاه 🔧\n'
        'عیب‌یابی ماشین با هوش مصنوعی — قبل از هزینه کردن، اول می‌فهمم.\n'
        '📲 دریافت نسخه اندروید از کافه‌بازار: $downloadUrl$referral';
  }

  /// متن کوتاه برای بخش «درباره» / پروفایل واتساپ
  static String whatsappAbout() {
    return 'عیب‌یابی ماشین با $appName 🔧 دریافت نسخه از کافه‌بازار: $downloadUrl';
  }

  /// دعوت کوتاه و طبیعی برای فرستادن به یک دوست یا همکار.
  /// اگر کد معرف کاربر موجود باشد، کد به پیام اضافه می‌شود.
  static String supportInvite({String? referralCode}) {
    final referral = (referralCode != null && referralCode.isNotEmpty)
        ? '\n\nبا کد معرف من ثبت‌نام کن و اعتبار هدیه بگیر:\n🎁 $referralCode'
        : '';
    return 'قبل از رفتن به تعمیرگاه این بررسی اولیه را امتحان کن 🔧\n'
        'مشکل ماشینت را بنویس یا صدای موتور را بفرست؛ یک سرنخ و چند سؤال کاربردی برای ادامه بررسی بگیر.\n\n'
        '📲 دریافت نسخه اندروید از کافه‌بازار:\n$downloadUrl'
        '$referral';
  }

  static Future<void> contactSupport() async {
    final uri = Uri(
      scheme: 'mailto',
      path: Constants.supportEmail,
      queryParameters: const {
        'subject': 'پیشنهاد برای مکانیک هوشمند',
        'body': 'سلام، پیشنهاد یا بازخورد من درباره مکانیک هوشمند:\n\n',
      },
    );
    final opened = await launchUrl(uri);
    if (!opened) throw StateError('برنامه ایمیل باز نشد');
  }

  static Future<void> shareApp({String? referralCode}) {
    return Share.share(
      appPitch(referralCode: referralCode),
      subject: 'دعوت به $appName',
    );
  }

  static String responseShare({
    required String result,
    String? carName,
    String? year,
  }) {
    final carLine = [
      if (carName != null && carName.trim().isNotEmpty) carName.trim(),
      if (year != null && year.trim().isNotEmpty) 'مدل ${year.trim()}',
    ].join(' · ');
    final contextLine = carLine.isEmpty ? '' : 'خودرو: $carLine\n';
    return '🔧 پاسخ مکانیک هوشمند\n$contextLine\n'
        '${result.trim()}\n\n'
        'این پاسخ راهنمای اولیه است و جایگزین بررسی تعمیرکار نیست.\n'
        '📲 دریافت نسخه اندروید از کافه‌بازار:\n$downloadUrl';
  }

  static Future<void> shareResponse({
    required String result,
    String? carName,
    String? year,
  }) {
    return Share.share(
      responseShare(result: result, carName: carName, year: year),
      subject: 'پاسخ مکانیک هوشمند',
    );
  }

  static Future<void> shareDiagnosis({
    required String result,
    String? carName,
    String? year,
    String? referralCode,
  }) {
    return Share.share(
      diagnosisShare(
        result: result,
        carName: carName,
        year: year,
        referralCode: referralCode,
      ),
      subject: 'نتیجه عیب‌یابی خودرو',
    );
  }

  static Future<void> shareToWhatsApp(String text) async {
    final uri = Uri.parse(
      'https://wa.me/?text=${Uri.encodeComponent(text)}',
    );
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        await Share.share(text, subject: appName);
      }
    } catch (_) {
      await Share.share(text, subject: appName);
    }
  }

  static Future<void> copy(String text) {
    return Clipboard.setData(ClipboardData(text: text));
  }
}
