import 'dart:async';

import 'package:flutter/material.dart';
import 'education_store.dart';
import 'bazaar_billing_service.dart';

class CreditShopPage extends StatefulWidget {
  const CreditShopPage({super.key, required this.store});

  final EducationStore store;

  @override
  State<CreditShopPage> createState() => _CreditShopPageState();
}

class _CreditShopPageState extends State<CreditShopPage> {
  late final BazaarBillingService _billing = BazaarBillingService(widget.store);

  String? _busyProduct;
  bool _restoring = false;

  bool get _isBusy => _busyProduct != null || _restoring;

  // ── تعریف بسته‌ها ──
  static const _packages = <_PackageInfo>[
    _PackageInfo(
      id: 'credit_10',
      title: 'بسته برنزی',
      credits: 10,
      creditsLabel: '۱۰ اعتبار',
      description: 'برای شروع و استفاده محدود',
      icon: Icons.bolt,
      color: Color(0xFFCD7F32), // برنز
    ),
    _PackageInfo(
      id: 'credit_35',
      title: 'بسته نقره‌ای',
      credits: 25,
      creditsLabel: '۲۵ اعتبار',
      description: 'انتخاب متعادل برای استفاده بیشتر',
      icon: Icons.bolt,
      color: Color(0xFFC0C0C0), // نقره‌ای
      popular: true,
    ),
    _PackageInfo(
      id: 'credit_90',
      title: 'بسته طلایی',
      credits: 60,
      creditsLabel: '۶۰ اعتبار',
      description: 'مناسب استفاده پرتکرار و به‌صرفه',
      icon: Icons.workspace_premium,
      color: Color(0xFFFFD700), // طلا
    ),
  ];

  // ══════════════════════════════════════════════
  //  عملیات خرید
  // ══════════════════════════════════════════════

  Future<void> _buy(String id) async {
    if (!_billing.isConfigured) {
      _showMessage('کلید عمومی بازار در نسخه فعلی تنظیم نشده است.');
      return;
    }

    setState(() => _busyProduct = id);

    try {
      await _billing.buy(id);
      if (!mounted) return;
      setState(() {}); // بازسازی اعتبار
      _showMessage('✅ خرید موفق! اعتبار به کیف پول اضافه شد.');
    } on BazaarBillingException catch (e) {
      if (!mounted) return;
      // لغو توسط کاربر → بدون پیام خطا
      if (e.isUserCancelled) return;
      _showMessage(e.message);
    } catch (e) {
      if (!mounted) return;
      _showMessage('خطای غیرمنتظره در فرآیند خرید.');
    } finally {
      if (mounted) setState(() => _busyProduct = null);
    }
  }

  // ══════════════════════════════════════════════
  //  بازیابی خریدها
  // ══════════════════════════════════════════════

  Future<void> _restore() async {
    if (!_billing.isConfigured) {
      _showMessage('کلید عمومی بازار در نسخه فعلی تنظیم نشده است.');
      return;
    }

    setState(() => _restoring = true);

    try {
      final count = await _billing.restorePurchases();
      if (!mounted) return;
      setState(() {}); // بازسازی اعتبار
      _showMessage(
        count > 0
            ? '✅ $count خرید بازیابی و اعتبار اضافه شد.'
            : 'خرید بازیابی‌نشده‌ای یافت نشد.',
      );
    } on BazaarBillingException catch (e) {
      if (!mounted) return;
      _showMessage(e.message);
    } catch (_) {
      if (!mounted) return;
      _showMessage('خطا در بازیابی خریدها.');
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  // ══════════════════════════════════════════════
  //  پیام‌رسانی
  // ══════════════════════════════════════════════

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text, textDirection: TextDirection.rtl),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }

  // ══════════════════════════════════════════════
  //  Lifecycle
  // ══════════════════════════════════════════════

  @override
  void dispose() {
    // dispose نمی‌تواند async باشد → unawaited
    unawaited(_billing.disconnect());
    super.dispose();
  }

  // ══════════════════════════════════════════════
  //  Build
  // ══════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      // جلوگیری از خروج حین خرید
      canPop: !_isBusy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isBusy) {
          _showMessage('لطفاً تا پایان فرآیند صبر کنید.');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('خرید اعتبار مشاور هوشمند'),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── کارت اعتبار باقی‌مانده ──
            _buildBalanceCard(theme),

            const SizedBox(height: 8),

            // ── توضیحات ──
            _buildInfoCard(theme),

            const SizedBox(height: 16),

            // ── لیست بسته‌ها ──
            ..._packages.map((pkg) => _buildPackageCard(pkg, theme)),

            const SizedBox(height: 16),

            // ── دکمه بازیابی ──
            _buildRestoreButton(),

            // ── هشدار عدم پیکربندی ──
            if (!_billing.isConfigured) _buildConfigWarning(),
          ],
        ),
      ),
    );
  }

  // ── کارت اعتبار ──
  Widget _buildBalanceCard(ThemeData theme) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(
              Icons.account_balance_wallet_outlined,
              size: 36,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Text(
                'اعتبار باقی‌مانده',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            // اگر store یک ValueNotifier/ChangeNotifier است:
            // ValueListenableBuilder<int>(
            //   valueListenable: widget.store.creditsNotifier,
            //   builder: (_, credits, __) => _creditText(credits),
            // ),
            _creditText(widget.store.credits),
          ],
        ),
      ),
    );
  }

  Widget _creditText(int credits) {
    return Text(
      credits.toString(),
      style: const TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w900,
      ),
    );
  }

  // ── کارت توضیحات ──
  Widget _buildInfoCard(ThemeData theme) {
    return Card(
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: const Padding(
        padding: EdgeInsets.all(14),
        child: Text(
          'دو درخواست موفق نخست رایگان است. پس از آن، برای هر پاسخ موفق '
          'هوش مصنوعی یک اعتبار مصرف می‌شود. در صورت خطا یا دریافت پاسخ '
          'نامعتبر، اعتباری کسر نمی‌شود. اعتبارهای خریداری‌شده روی همین '
          'گوشی نگهداری می‌شوند.',
          style: TextStyle(height: 1.8, fontSize: 13),
          textDirection: TextDirection.rtl,
        ),
      ),
    );
  }

  // ── کارت بسته ──
  Widget _buildPackageCard(_PackageInfo pkg, ThemeData theme) {
    final isBusy = _busyProduct == pkg.id;
    final isDisabled = _isBusy;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        elevation: pkg.popular ? 3 : 1,
        shape: pkg.popular
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 1.5,
                ),
              )
            : null,
        child: Stack(
          children: [
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              leading: CircleAvatar(
                backgroundColor: pkg.color.withValues(alpha: 0.15),
                child: Icon(pkg.icon, color: pkg.color),
              ),
              title: Row(
                children: [
                  Text(
                    pkg.title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (pkg.popular) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'پرفروش',
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${pkg.creditsLabel} · ${pkg.description}\n'
                  'قیمت نهایی در پنجره پرداخت بازار نمایش داده می‌شود.',
                  style: const TextStyle(height: 1.5),
                ),
              ),
              isThreeLine: true,
              trailing: FilledButton(
                onPressed: isDisabled ? null : () => _buy(pkg.id),
                style: FilledButton.styleFrom(
                  backgroundColor: pkg.color.withValues(alpha: 0.85),
                  foregroundColor: Colors.white,
                ),
                child: isBusy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('خرید'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── دکمه بازیابی ──
  Widget _buildRestoreButton() {
    return OutlinedButton.icon(
      onPressed: _isBusy ? null : _restore,
      icon: _restoring
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.restore),
      label: const Text('بررسی و بازیابی خریدهای بازار'),
    );
  }

  // ── هشدار عدم پیکربندی ──
  Widget _buildConfigWarning() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        color: Colors.deepOrange.shade50,
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.deepOrange),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'خرید در این نسخه فعال نیست.\n'
                  'BAZAAR_RSA_PUBLIC_KEY باید هنگام ساخت APK تزریق شود.',
                  style: TextStyle(
                    color: Colors.deepOrange,
                    height: 1.6,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  مدل بسته اعتباری
// ═══════════════════════════════════════════════════════════

class _PackageInfo {
  const _PackageInfo({
    required this.id,
    required this.title,
    required this.credits,
    required this.creditsLabel,
    required this.description,
    required this.icon,
    required this.color,
    this.popular = false,
  });

  final String id;
  final String title;
  final int credits;
  final String creditsLabel;
  final String description;
  final IconData icon;
  final Color color;
  final bool popular;
}
