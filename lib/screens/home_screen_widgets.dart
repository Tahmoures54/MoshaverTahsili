part of 'home_screen.dart';

// Private UI pieces for HomeScreen (must stay a `part of` — no own imports).

// =============================================================================
// ثابت‌های محلی — شدت‌های opacity در یک‌جا جمع شده تا تغییر رنگ برند در آینده
// فقط با ویرایش همین چند خط ممکن باشد.
// اعداد ۰٫۱۲ و ۰٫۳۸ مطابق توکن‌های استاندارد Material 3 برای حالت غیرفعال است.
// =============================================================================
const double _kIconBgOpacity = 0.14;
const double _kSubtitleOpacity = 0.82;
const double _kShadowOpacity = 0.45;
const double _kBorderOpacity = 0.55;
const double _kSoftBgOpacity = 0.12;
const double _kM3DisabledContainerOpacity = 0.12;
const double _kM3DisabledContentOpacity = 0.38;

/// اگر مقدار null یا خالی بود «—» نشان بده؛ برای جلوگیری از نمایش لفظی
/// "null" وقتی پروفایل هنوز لود نشده یا مقداری برنگشته است.
String _orDash(Object? value) {
  if (value == null) return '—';
  final text = value.toString();
  return text.isEmpty ? '—' : text;
}

/// ارقام فارسی/عربی را حین تایپ به لاتین تبدیل می‌کند و هر کاراکتر غیرعددی
/// را بی‌صدا حذف می‌کند.
///
/// چرا لازم است: `FilteringTextInputFormatter.digitsOnly` فقط ارقام لاتین
/// (0-9) را قبول می‌کند؛ کاربری که با کیبورد فارسی پیش‌فرض «۱۴۰۲» تایپ کند،
/// می‌بیند که هیچ‌چیز در فیلد ظاهر نمی‌شود. این formatter هر دو دسته رقم را
/// می‌پذیرد و بلافاصله به لاتین نرمال می‌کند تا هم تجربهٔ تایپ سالم بماند
/// هم مقدار خروجی همیشه با فرمتی که ولیدیشن انتظار دارد یکی باشد.
class _DigitInputFormatter extends TextInputFormatter {
  const _DigitInputFormatter();

  static const Map<String, String> _toLatin = {
    '۰': '0', '۱': '1', '۲': '2', '۳': '3', '۴': '4',
    '۵': '5', '۶': '6', '۷': '7', '۸': '8', '۹': '9',
    '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4',
    '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
  };

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final buffer = StringBuffer();
    for (final ch in newValue.text.split('')) {
      final mapped = _toLatin[ch];
      if (mapped != null) {
        buffer.write(mapped);
      } else if (RegExp(r'[0-9]').hasMatch(ch)) {
        buffer.write(ch);
      }
      // هر کاراکتر دیگر (حرف، فاصله، نماد) بی‌صدا نادیده گرفته می‌شود.
    }
    final newText = buffer.toString();
    // برای فیلد کوتاهی مثل سال ساخت، نگه‌داشتن مکان‌نما در انتها ساده‌ترین
    // و امن‌ترین رفتار است (مشابه رفتار رایج فیلدهای OTP/مبلغ).
    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}

class _DiagnoseCtaButton extends StatelessWidget {
  final VoidCallback? onPressed;
  const _DiagnoseCtaButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = onPressed == null;
    final bg = disabled
        ? theme.colorScheme.onSurface.withOpacity(_kM3DisabledContainerOpacity)
        : theme.colorScheme.secondary;
    final fg = disabled
        ? theme.colorScheme.onSurface.withOpacity(_kM3DisabledContentOpacity)
        : theme.colorScheme.onSecondary;

    return Semantics(
      button: true,
      enabled: !disabled,
      label: 'ارسال شرح مشکل به مکانیک هوشمند',
      child: Material(
        color: bg,
        elevation: disabled ? 0 : 3,
        shadowColor: theme.colorScheme.secondary.withOpacity(_kShadowOpacity),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(_kIconBgOpacity),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.send_rounded, color: fg, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ارسال به مکانیک هوشمند',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: fg,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'تحلیل اولیه با کمک هوش مصنوعی',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: fg.withOpacity(_kSubtitleOpacity),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.auto_awesome_rounded, color: fg, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


class _SectionLabel extends StatelessWidget {
  final String number;
  final String title;
  const _SectionLabel({required this.number, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: theme.colorScheme.secondary,
          child: Text(
            number,
            style: TextStyle(color: theme.colorScheme.onSecondary, fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 10),
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _CarCard extends StatelessWidget {
  final bool isCustom;
  final List<Car> cars;
  final Car? selectedCar;
  final bool isLoading;
  final bool hasError;
  final TextEditingController customController;
  final TextEditingController yearController;
  final VoidCallback onRetry;
  final ValueChanged<Car> onCarSelected;
  final VoidCallback onToggleCustom;

  const _CarCard({
    required this.isCustom,
    required this.cars,
    required this.selectedCar,
    required this.isLoading,
    required this.hasError,
    required this.customController,
    required this.yearController,
    required this.onRetry,
    required this.onCarSelected,
    required this.onToggleCustom,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isCustom)
              CarSelectorWidget(
                cars: cars,
                selectedCar: selectedCar,
                isLoading: isLoading,
                hasError: hasError,
                onRetry: onRetry,
                onCarSelected: onCarSelected,
              )
            else
              TextField(
                controller: customController,
                textInputAction: TextInputAction.next,
                maxLength: 40,
                decoration: const InputDecoration(
                  labelText: 'نام خودرو',
                  hintText: 'مثلاً: تویوتا کمری',
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: yearController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              // به‌جای digitsOnly (که ارقام فارسی/عربی را کاملاً رد می‌کند
              // و باعث می‌شود فیلد برای بخش زیادی از کاربران خالی بماند)،
              // این formatter هر دو دسته رقم را می‌پذیرد و به لاتین تبدیل
              // می‌کند تا هم تایپ روان باشد هم خروجی همیشه یک‌دست بماند.
              inputFormatters: const [_DigitInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'سال ساخت',
                hintText: 'مثلاً ۱۴۰۲ یا 2023',
                counterText: '',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onToggleCustom,
              child: Text(isCustom ? 'انتخاب از لیست خودروها' : 'خودروی من در لیست نیست'),
            ),
          ],
        ),
      ),
    );
  }
}


class _MechanicAllyCard extends StatelessWidget {
  const _MechanicAllyCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          'مکانیک هوشمند کمکت می‌کند قبل از مراجعه، تصویر روشن‌تری از مشکل داشته باشی — نه جایگزین مکانیک متخصص.',
          style: TextStyle(height: 1.5, color: Theme.of(context).hintColor),
        ),
      ),
    );
  }
}

class _WhyItWorksSection extends StatelessWidget {
  const _WhyItWorksSection();

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('چرا مکانیک هوشمند؟', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('قبل از اینکه پولی برای تعمیر خرج کنی، کمک می‌کنیم بهتر بفهمی چه چیزی ممکن است مشکل داشته باشد.', style: TextStyle(fontSize: 13, height: 1.55, color: Theme.of(context).hintColor)),
            const SizedBox(height: 12),
            _BenefitRow(
              icon: Icons.favorite_border_rounded,
              title: 'قبل از خرج کردن، اول بفهم',
              text: 'گاهی یک مشکل ساده با یک تصمیم عجولانه تبدیل به هزینه‌ای غیرضروری می‌شود. مکانیک هوشمند کمک می‌کند قبل از مراجعه، تصویر روشن‌تری از نشانه‌ها و علت‌های احتمالی داشته باشی.',
            ),
            _BenefitRow(
              icon: Icons.payments_outlined,
              title: 'برای هزینه‌های الکی آماده نیستی',
              text: 'کمک می‌کنیم بی‌دلیل قطعه عوض نکنی یا برای کاری که لازم نیست هزینه ندهی. سؤال‌های درست‌تر بپرس و با آگاهی بیشتری درباره تعمیر تصمیم بگیر.',
            ),
            _BenefitRow(
              icon: Icons.support_agent_rounded,
              title: 'یک همراه دلسوز قبل از تعمیرگاه',
              text: 'مکانیک هوشمند جای مکانیک متخصص را نمی‌گیرد؛ قبل از مراجعه کنارت است تا کمتر سردرگم شوی و با اطمینان بیشتری صحبت کنی.',
            ),
            _BenefitRow(
              icon: Icons.savings_rounded,
              title: 'هزینه ناچیز، خیال راحت‌تر',
              text: 'اگر همین راهنمایی قبل از تعمیر جلوی یک خرج اشتباه را بگیرد، هزینه ناچیز یک بررسی هوشمند ارزش خودش را پیدا می‌کند. هدف ما کمک به توست، نه بیشتر خرج کردنت.',
            ),
          ],
        ),
      ),
    );
  }
}

class _BenefitRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  const _BenefitRow({required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: theme.colorScheme.secondary, size: 23),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: DefaultTextStyle.of(context).style.copyWith(height: 1.45),
                children: [
                  TextSpan(text: '$title: ', style: const TextStyle(fontWeight: FontWeight.w800)),
                  TextSpan(text: text),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GrowthShareBanner extends StatelessWidget {
  const _GrowthShareBanner();

  Future<void> _share(BuildContext context) async {
    try {
      final code = context.read<AuthProvider>().referralCode;
      await ShareService.shareApp(referralCode: code);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اشتراک‌گذاری انجام نشد. دوباره تلاش کنید.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = context.watch<AuthProvider>().referralCode;
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 12, 15),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.secondary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.share_rounded, color: theme.colorScheme.secondary, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'یک دوست صاحب خودرو را هم دعوت کن',
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    code?.isNotEmpty == true
                        ? 'با کد معرفت دعوت کن و اگر دوستت ثبت‌نام کرد، پاداش معرفی طبق شرایط حساب می‌شود.'
                        : 'اگر این ابزار به کارت آمد، لینک آن را برای یک دوست بفرست.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: theme.hintColor, fontSize: 11.5, height: 1.45),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'اشتراک‌گذاری',
              onPressed: () => _share(context),
              icon: Icon(Icons.ios_share_rounded, color: theme.colorScheme.secondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportCard extends StatelessWidget {
  const _SupportCard();

  Future<void> _runSupportAction(
    BuildContext context,
    BuildContext sheetContext,
    Future<void> Function() action, {
    String? successMessage,
    bool closeSheet = true,
  }) async {
    try {
      await action();
      if (closeSheet && sheetContext.mounted) Navigator.pop(sheetContext);
      if (successMessage != null && context.mounted) {
        _showSupportSnack(context, successMessage);
      }
    } catch (_) {
      if (closeSheet && sheetContext.mounted) Navigator.pop(sheetContext);
      if (context.mounted) {
        _showSupportSnack(context, 'این عملیات انجام نشد. لطفاً دوباره تلاش کنید.');
      }
    }
  }

  Future<void> _openSupportSheet(BuildContext context) async {
    final theme = Theme.of(context);
    // کد معرف کاربر — برای اینکه پیام‌های دعوت، اعتبار معرف را برای
    // دعوت‌کننده محفوظ نگه دارند.
    final referralCode = context.read<AuthProvider>().referralCode;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary.withOpacity(_kSoftBgOpacity),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: theme.colorScheme.secondary.withOpacity(0.22)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.volunteer_activism_rounded, color: theme.colorScheme.secondary, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'بهترین حمایت، معرفی به یک دوست صاحب خودرو یا گفتن یک پیشنهاد خوب است؛ همهٔ گزینه‌ها رایگان‌اند.',
                        style: TextStyle(color: theme.colorScheme.onSurface, height: 1.5, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _SupportActionTile(
                icon: Icons.person_add_alt_1_rounded,
                title: 'دعوت از یک دوست صاحب خودرو',
                subtitle: 'پیام کوتاه و طبیعی را با هر برنامه‌ای بفرست',
                emphasized: true,
                onTap: () => _runSupportAction(
                  context,
                  sheetContext,
                  () => ShareService.shareApp(referralCode: referralCode),
                ),
              ),
              _SupportActionTile(
                icon: Icons.chat_rounded,
                title: 'ارسال مستقیم در واتساپ',
                subtitle: 'برای یک نفر یا یک گروه واتساپی',
                onTap: () => _runSupportAction(
                  context,
                  sheetContext,
                  () => ShareService.shareToWhatsApp(
                      ShareService.supportInvite(referralCode: referralCode)),
                ),
              ),
              _SupportActionTile(
                icon: Icons.content_copy_rounded,
                title: 'کپی پیام معرفی',
                subtitle: 'برای هر پیام‌رسان یا شبکه‌ای که دوست داری',
                onTap: () => _runSupportAction(
                  context,
                  sheetContext,
                  () => ShareService.copy(
                      ShareService.supportInvite(referralCode: referralCode)),
                  successMessage: 'پیام معرفی کپی شد.',
                ),
              ),
              _SupportActionTile(
                icon: Icons.account_circle_rounded,
                title: 'لینک را در پروفایل واتساپ بگذارم',
                subtitle: 'متن کوتاه و آمادهٔ پروفایل',
                onTap: () => _runSupportAction(
                  context,
                  sheetContext,
                  () => ShareService.copy(ShareService.whatsappAbout()),
                  successMessage: 'متن پروفایل واتساپ کپی شد.',
                ),
              ),
              _SupportActionTile(
                icon: Icons.feedback_outlined,
                title: 'پیشنهاد یا بازخورد برای ما',
                subtitle: Constants.supportEmail,
                onTap: () => _runSupportAction(
                  context,
                  sheetContext,
                  ShareService.contactSupport,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showSupportSnack(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openSupportSheet(context),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondary.withOpacity(_kSoftBgOpacity),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(Icons.favorite_rounded, color: theme.colorScheme.secondary, size: 27),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('حمایت از یک استارتاپ نوپا', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                        SizedBox(height: 3),
                        Text(
                          'یک معرفی ساده می‌تواند به رشد مکانیک هوشمند کمک کند.',
                          style: TextStyle(fontSize: 12.5, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_left_rounded),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'اگر این اپ قبل از تعمیرگاه کمکت کرد، یک دوست صاحب خودرو را هم با آن آشنا کن. یک معرفی کوتاه از ده‌ها تبلیغ ارزشمندتر است.',
                style: TextStyle(color: theme.hintColor, height: 1.55, fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () => _openSupportSheet(context),
                icon: const Icon(Icons.volunteer_activism_rounded, size: 19),
                label: const Text('حمایت در یک لمس'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupportActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool emphasized;

  const _SupportActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: emphasized
              ? BorderSide(color: theme.colorScheme.secondary.withOpacity(0.45))
              : BorderSide.none,
        ),
        tileColor: emphasized
            ? theme.colorScheme.secondary.withOpacity(_kSoftBgOpacity)
            : theme.cardColor,
        leading: CircleAvatar(
          radius: 18,
          backgroundColor: emphasized
              ? theme.colorScheme.secondary.withOpacity(0.22)
              : theme.colorScheme.secondary.withOpacity(_kSoftBgOpacity),
          child: Icon(icon, color: theme.colorScheme.secondary, size: 19),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
        subtitle: Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5)),
        trailing: Icon(
          emphasized ? Icons.ios_share_rounded : Icons.arrow_back_ios_rounded,
          size: emphasized ? 18 : 14,
          color: emphasized ? theme.colorScheme.secondary : null,
        ),
        onTap: onTap,
      ),
    );
  }
}
