import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../constants.dart';

class DisclaimerScreen extends StatefulWidget {
  /// اگر true باشد، کاربر باید قبول کند تا بتواند ادامه دهد
  final bool requireAcceptance;
  final VoidCallback? onAccepted;

  const DisclaimerScreen({
    super.key,
    this.requireAcceptance = false,
    this.onAccepted,
  });

  @override
  State<DisclaimerScreen> createState() => _DisclaimerScreenState();
}

class _DisclaimerScreenState extends State<DisclaimerScreen> {
  final ScrollController _scrollCtrl = ScrollController();
  bool _hasScrolledToBottom = false;
  bool _isAccepted = false;

  @override
  void initState() {
    super.initState();
    if (widget.requireAcceptance) {
      _scrollCtrl.addListener(_onScroll);
    } else {
      _hasScrolledToBottom = true;
    }
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_hasScrolledToBottom) return;
    final pos = _scrollCtrl.position;
    // وقتی کاربر به ۹۵٪ انتهای صفحه رسید
    if (pos.pixels >= pos.maxScrollExtent * 0.95) {
      setState(() => _hasScrolledToBottom = true);
    }
  }

  Future<void> _launchEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: Constants.supportEmail,
      query: 'subject=سوال حقوقی - ${Constants.appName}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: Constants.supportEmail));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('ایمیل کپی شد'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green.shade700,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  void _onAccept() {
    if (!_isAccepted || !_hasScrolledToBottom) return;
    widget.onAccepted?.call();
    if (Navigator.canPop(context)) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'شرایط و سلب مسئولیت',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          // ── دکمه کپی کل متن ──
          IconButton(
            tooltip: 'کپی متن',
            icon: const Icon(Icons.copy_rounded, size: 20),
            onPressed: () async {
              await Clipboard.setData(
                const ClipboardData(text: _DisclaimerContent.fullText),
              );
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('متن کامل کپی شد'),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: Colors.green.shade700,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── هدر ──
            _buildHeader(theme),

            // ── محتوا ──
            Expanded(
              child: ListView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  ..._DisclaimerContent.sections.map(
                    (s) => _SectionCard(section: s, theme: theme),
                  ),
                  const SizedBox(height: 8),
                  // ── دکمه تماس ──
                  _buildContactRow(theme),
                  const SizedBox(height: 8),
                  // ── تاریخ ──
                  Center(
                    child: Text(
                      'آخرین به‌روزرسانی: ۲۳ تیر ۱۴۰۵',
                      style: TextStyle(
                        color: theme.hintColor,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),

            // ── بخش پذیرش (اختیاری) ──
            if (widget.requireAcceptance)
              _buildAcceptanceSection(theme),
          ],
        ),
      ),
    );
  }

  // ── هدر هشدار ──
  Widget _buildHeader(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.orange, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'لطفاً پیش از استفاده، این شرایط را به دقت مطالعه کنید.',
              style: TextStyle(
                color: Colors.orange.shade300,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── ردیف تماس ──
  Widget _buildContactRow(ThemeData theme) {
    return InkWell(
      onTap: _launchEmail,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          children: [
            Icon(Icons.email_rounded,
                color: theme.colorScheme.secondary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'تماس و سوالات حقوقی',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.secondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    Constants.supportEmail,
                    style: TextStyle(
                      color: theme.hintColor,
                      fontSize: 12,
                    ),
                    textDirection: TextDirection.ltr,
                  ),
                ],
              ),
            ),
            Icon(Icons.open_in_new_rounded,
                size: 16, color: theme.hintColor),
          ],
        ),
      ),
    );
  }

  // ── بخش پذیرش ──
  Widget _buildAcceptanceSection(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(top: BorderSide(color: theme.dividerColor)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── نشانگر اسکرول ──
          if (!_hasScrolledToBottom)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.keyboard_arrow_down_rounded,
                      color: theme.colorScheme.secondary, size: 18),
                  Text(
                    'برای فعال‌شدن دکمه، تا انتها اسکرول کنید',
                    style: TextStyle(
                      color: theme.colorScheme.secondary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),

          // ── چک‌باکس ──
          Row(
            children: [
              Checkbox(
                value: _isAccepted,
                activeColor: theme.colorScheme.secondary,
                onChanged: _hasScrolledToBottom
                    ? (v) => setState(() => _isAccepted = v ?? false)
                    : null,
              ),
              Expanded(
                child: GestureDetector(
                  onTap: _hasScrolledToBottom
                      ? () =>
                          setState(() => _isAccepted = !_isAccepted)
                      : null,
                  child: Text(
                    'شرایط و سلب مسئولیت را مطالعه کرده و می‌پذیرم.',
                    style: TextStyle(
                      fontSize: 13,
                      color: _hasScrolledToBottom
                          ? theme.textTheme.bodyLarge?.color
                          : theme.hintColor,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ── دکمه پذیرش ──
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_isAccepted && _hasScrolledToBottom)
                  ? _onAccept
                  : null,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                backgroundColor: theme.colorScheme.secondary,
                foregroundColor: Colors.black,
                disabledBackgroundColor:
                    theme.colorScheme.secondary.withOpacity(0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'پذیرش و ادامه',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ── کارت هر بخش ──
// ─────────────────────────────────────────────────────────────────────────────
class _SectionCard extends StatelessWidget {
  final _DisclaimerSection section;
  final ThemeData theme;

  const _SectionCard({required this.section, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
        ),
        child: ExpansionTile(
          initiallyExpanded: section.isImportant,
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: section.iconColor.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              section.icon,
              color: section.iconColor,
              size: 18,
            ),
          ),
          title: Text(
            section.title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          trailing: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: theme.hintColor,
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(color: theme.dividerColor),
                  const SizedBox(height: 4),
                  ...section.items.map(
                    (item) => _buildItem(item),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(String item) {
    final isBullet = item.startsWith('•');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        item,
        style: TextStyle(
          fontSize: 13,
          height: 1.7,
          color: isBullet
              ? theme.textTheme.bodyMedium?.color
              : theme.textTheme.bodyLarge?.color,
        ),
        textDirection: TextDirection.rtl,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ── مدل و محتوای بخش‌ها ──
// ─────────────────────────────────────────────────────────────────────────────
class _DisclaimerSection {
  final String title;
  final List<String> items;
  final IconData icon;
  final Color iconColor;
  final bool isImportant;

  const _DisclaimerSection({
    required this.title,
    required this.items,
    required this.icon,
    required this.iconColor,
    this.isImportant = false,
  });
}

class _DisclaimerContent {
  _DisclaimerContent._();

  static const List<_DisclaimerSection> sections = [
    _DisclaimerSection(
      title: '۱. ماهیت خدمات',
      icon: Icons.info_outline_rounded,
      iconColor: Colors.blue,
      isImportant: true,
      items: [
        'برنامه «مکانیک هوشمند» یک ابزار تفریحی-اطلاعاتی است.',
        'با استفاده از هوش مصنوعی و پردازش زبان طبیعی، '
            'پیشنهادهایی برای تشخیص مشکلات احتمالی خودرو ارائه می‌کند.',
        '⚠️ این پیشنهادها نظر تخصصی تلقی نشده و صرفاً جهت آگاهی اولیه کاربر عرضه می‌شوند.',
      ],
    ),
    _DisclaimerSection(
      title: '۲. عدم ضمانت',
      icon: Icons.gpp_maybe_rounded,
      iconColor: Colors.orange,
      isImportant: true,
      items: [
        'توسعه‌دهنده(گان) هیچ‌گونه ضمانتی، صریح یا ضمنی، ارائه نمی‌دهند.',
        'این ضمانت شامل موارد زیر می‌شود:',
        '• صحت نتایج',
        '• کامل بودن اطلاعات',
        '• قابلیت اطمینان',
        '• مناسب بودن برای هدف خاص',
        'تشخیص نهایی و تصمیم‌گیری در مورد تعمیرات، تنها بر عهده مکانیک متخصص و کاربر است.',
      ],
    ),
    _DisclaimerSection(
      title: '۳. محدودیت مسئولیت',
      icon: Icons.shield_outlined,
      iconColor: Colors.red,
      isImportant: true,
      items: [
        'تحت هیچ شرایطی، توسعه‌دهنده در قبال موارد زیر مسئول نخواهد بود:',
        '• آسیب‌های جانی، مالی یا زیست‌محیطی ناشی از تعمیرات اشتباه',
        '• خرابی قطعات خودرو یا کاهش ارزش آن',
        '• هزینه‌های تعمیر، یدک‌کش یا توقف خودرو',
        '• از دست رفتن داده‌ها، سود یا فرصت‌های تجاری',
        '• هرگونه ادعای شخص ثالث',
      ],
    ),
    _DisclaimerSection(
      title: '۴. مالکیت معنوی',
      icon: Icons.copyright_rounded,
      iconColor: Colors.purple,
      items: [
        'تمامی کدها، رابط کاربری، متون و محتوای تولیدشده متعلق به توسعه‌دهنده است.',
        'اطلاعات خودرویی ارائه‌شده توسط کاربر، محرمانه تلقی شده و '
            'جز برای ارائه خدمات استفاده نمی‌شود.',
      ],
    ),
    _DisclaimerSection(
      title: '۵. خدمات شخص ثالث',
      icon: Icons.api_rounded,
      iconColor: Colors.teal,
      items: [
        'نرم‌افزار از APIهای خارجی (مانند Google Maps) استفاده می‌کند.',
        'توسعه‌دهنده هیچ مسئولیتی در قبال عملکرد، حریم خصوصی '
            'یا خطاهای این سرویس‌ها ندارد.',
      ],
    ),
    _DisclaimerSection(
      title: '۶. تغییرات',
      icon: Icons.update_rounded,
      iconColor: Colors.cyan,
      items: [
        'این سلب مسئولیت ممکن است بدون اطلاع قبلی به‌روزرسانی شود.',
        'ادامه استفاده از نرم‌افزار به معنای پذیرش نسخه جدید است.',
      ],
    ),
    _DisclaimerSection(
      title: '۷. پذیرش',
      icon: Icons.check_circle_outline_rounded,
      iconColor: Colors.green,
      items: [
        'با نصب، اجرا یا استفاده از نرم‌افزار، تأیید می‌کنید که:',
        '• این سند را به‌طور کامل مطالعه کرده‌اید.',
        '• شرایط آن را بدون قید و شرط پذیرفته‌اید.',
        'در صورت عدم موافقت، باید فوراً نرم‌افزار را حذف نمایید.',
      ],
    ),
  ];

  // ── متن کامل برای کپی ──
  static const String fullText = '''
سلب مسئولیت و شرایط استفاده – مکانیک هوشمند
آخرین به‌روزرسانی: ۲۳ تیر ۱۴۰۵

۱. ماهیت خدمات
برنامه «مکانیک هوشمند» یک ابزار تفریحی-اطلاعاتی است که با استفاده از هوش مصنوعی و پردازش زبان طبیعی، پیشنهادهایی برای تشخیص مشکلات احتمالی خودرو ارائه می‌کند. این پیشنهادها نظر تخصصی تلقی نشده و صرفاً جهت آگاهی اولیه کاربر عرضه می‌شوند.

۲. عدم ضمانت
توسعه‌دهنده(گان) هیچ‌گونه ضمانتی در مورد صحت، کامل بودن، قابلیت اطمینان یا مناسب بودن نتایج ارائه نمی‌دهند.

۳. محدودیت مسئولیت
توسعه‌دهنده در قبال هیچ‌گونه خسارتی مسئول نخواهد بود.

۴. مالکیت معنوی
تمامی کدها و محتوا متعلق به توسعه‌دهنده است.

۵. خدمات شخص ثالث
توسعه‌دهنده مسئولیتی در قبال سرویس‌های خارجی ندارد.

۶. تغییرات
این سند ممکن است بدون اطلاع به‌روزرسانی شود.

۷. پذیرش
با استفاده از نرم‌افزار، این شرایط را می‌پذیرید.
''';
}
