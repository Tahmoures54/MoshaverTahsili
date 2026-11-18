import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui.dart';

const simorghBazaarUrl = 'https://cafebazaar.ir/app/ir.moshaver.tahsili';
const simorghReferralMessage =
    'من از برنامه «سیمرغ؛ مشاور هوشمند تحصیلی» برای برنامه‌ریزی و مسیر یادگیری استفاده می‌کنم. '
    'اگر دوست داری تو هم امتحانش کنی، از این لینک نصبش کن:\n'
    '$simorghBazaarUrl';

class ReferralPage extends StatelessWidget {
  const ReferralPage({super.key});

  static const _shareChannel = MethodChannel('ir.moshaver.tahsili/share');

  Future<void> _share(BuildContext context) async {
    try {
      await _shareChannel.invokeMethod<bool>('shareText', {
        'text': simorghReferralMessage,
      });
    } on PlatformException {
      if (context.mounted) {
        showMessage(context, 'باز کردن پنجره اشتراک‌گذاری ممکن نشد. لینک را کپی کن.');
      }
    } on MissingPluginException {
      if (context.mounted) {
        showMessage(context, 'اشتراک‌گذاری در این دستگاه در دسترس نیست. لینک را کپی کن.');
      }
    }
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(const ClipboardData(text: simorghReferralMessage));
    if (context.mounted) showMessage(context, 'متن معرفی و لینک کپی شد.');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('معرفی سیمرغ به دوستان')),
    body: ListView(
      padding: const EdgeInsets.all(18),
      children: [
        const SizedBox(height: 8),
        const Center(child: SimorghMark(size: 112)),
        const SizedBox(height: 18),
        const Text('یادگیری با همراهی دوستان شیرین‌تر است!',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        const Text(
          'سیمرغ را به هم‌کلاسی‌ها و دوستانت معرفی کن تا آن‌ها هم با ابزارهای برنامه‌ریزی، مرور و راهنمایی تحصیلی آشنا شوند.',
          textAlign: TextAlign.center,
          style: TextStyle(height: 1.9, color: Colors.blueGrey),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('متن آماده معرفی',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                const SelectableText(
                  simorghReferralMessage,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(height: 1.9),
                ),
                const Divider(height: 26),
                const Text('لینک رسمی نصب از کافه‌بازار',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const SelectableText(
                  simorghBazaarUrl,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(color: blue, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () => _share(context),
          icon: const Icon(Icons.share_outlined),
          label: const Text('معرفی به دوستان'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _copy(context),
          icon: const Icon(Icons.copy_outlined),
          label: const Text('کپی متن و لینک'),
        ),
        const SizedBox(height: 12),
        const NoticeCard(
          icon: Icons.privacy_tip_outlined,
          text: 'برای معرفی برنامه، اطلاعات شخصی یا شماره تماس تو ارسال نمی‌شود. فقط متنی که در بالا می‌بینی و لینک عمومی کافه‌بازار در اختیار برنامه اشتراک‌گذاری گوشی قرار می‌گیرد.',
        ),
      ],
    ),
  );
}
