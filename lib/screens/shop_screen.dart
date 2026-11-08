import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/shop_package.dart';
import '../providers/auth_provider.dart';
import '../services/bazaar_billing_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ── صفحه فروشگاه ──
// ─────────────────────────────────────────────────────────────────────────────
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  String? _loadingProductId;
  List<ShopPackage> _products = shopPackages;
  bool _productsLoading = true;

  Future<void> _loadProducts() async {
    if (mounted) {
      setState(() {
        _products = shopPackages;
        _productsLoading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AuthProvider>().refreshLocalState();
      _loadProducts();
      unawaited(_restorePurchases());
    });
  }

  Future<void> _restorePurchases() async {
    try {
      await context.read<BazaarBillingService>().restorePurchases();
      if (mounted) await context.read<AuthProvider>().refreshLocalState();
    } catch (e) {
      // The screen remains usable when Bazaar is unavailable or the user is
      // not signed in to the Bazaar app.
      debugPrint('[ShopScreen] restore purchases skipped: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // کمکی‌ها
  // ---------------------------------------------------------------------------

  void _showSnack(String msg, {Color color = Colors.green}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  String _formatToman(int amount) {
    final s = amount.abs().toString();
    final formatted = s.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    final sign = amount < 0 ? '-' : '';
    return '$sign$formatted تومان';
  }

  // ---------------------------------------------------------------------------
  // خرید بسته
  // ---------------------------------------------------------------------------

  Future<void> _buyProduct(String productId) async {
    if (_loadingProductId != null) return;
    setState(() => _loadingProductId = productId);
    try {
      await context.read<BazaarBillingService>().buy(productId);
      if (!mounted) return;
      await context.read<AuthProvider>().refreshLocalState();
      _showSnack('خرید با موفقیت ثبت شد.');
    } on BazaarBillingException catch (e) {
      if (mounted) _showSnack(e.message, color: Colors.redAccent);
    } catch (e) {
      debugPrint('[ShopScreen] Bazaar purchase failed: $e');
      if (mounted) {
        _showSnack(
          'پرداخت کامل نشد. بازار را بررسی کنید و دوباره تلاش کنید.',
          color: Colors.redAccent,
        );
      }
    } finally {
      if (mounted) setState(() => _loadingProductId = null);
    }
  }

  // ---------------------------------------------------------------------------
  // build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('اعتبار و اشتراک'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: () => auth.refreshLocalState(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _buildWalletCard(auth, theme),
            const SizedBox(height: 20),
            Text(
              'بسته‌ها',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'هرچه بیشتر بخرید، هر عیب‌یابی ارزان‌تر تمام می‌شود',
              style: TextStyle(color: theme.hintColor, fontSize: 13),
            ),
            const SizedBox(height: 14),
            ..._products.map((p) => _buildPackageCard(p, theme)),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 14, color: theme.hintColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'تمام بسته‌ها اعتبار کل مشخص دارند و محدودیت روزانه ندارند. '
                    'پس از دو عیب‌یابی رایگان، هر عیب‌یابی موفق یک اعتبار کم می‌کند؛ '
                    'با تمام شدن اعتبار باید بسته جدید بخرید.',
                    style: TextStyle(color: theme.hintColor, fontSize: 11, height: 1.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildTrustFooter(theme),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // کارت کیف پول
  // ---------------------------------------------------------------------------

  Widget _buildWalletCard(AuthProvider auth, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            theme.colorScheme.primary.withOpacity(0.85),
            theme.colorScheme.secondary.withOpacity(0.75),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                auth.isGoldenActive
                    ? Icons.workspace_premium
                    : Icons.account_balance_wallet_rounded,
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'کیف اعتبار شما',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _walletStat(
                  // «نامحدود» گمراه‌کننده است؛ اشتراک طلایی سقف مصرف
                  // منصفانه دارد (روی کارت بسته مشخص است).
                  label: 'اعتبار باقی‌مانده',
                  value: '${auth.credits}',
                  icon: Icons.bolt_rounded,
                ),
              ),
              Container(width: 1, height: 40, color: Colors.white24),
              Expanded(
                child: _walletStat(
                  label: 'وضعیت',
                  value:
                      auth.canDiagnose ? 'آماده عیب‌یابی' : 'نیاز به شارژ',
                  icon: auth.canDiagnose
                      ? Icons.check_circle_rounded
                      : Icons.warning_amber_rounded,
                ),
              ),
            ],
          ),
          if (!auth.canDiagnose) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'برای ادامه عیب‌یابی یکی از بسته‌های زیر را انتخاب کنید.',
                style: TextStyle(color: Colors.white, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _walletStat({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // کارت بسته
  // ---------------------------------------------------------------------------

  Widget _buildPackageCard(ShopPackage pkg, ThemeData theme) {
    final isLoadingThis = _loadingProductId == pkg.id;
    final isAnyLoading = _loadingProductId != null;
    final unit = pkg.unitPrice;
    final isHighlighted = pkg.isPopular || pkg.isBestValue;
    final isGold = pkg.isGold;

    final cardColor = isGold
        ? Colors.amber.withOpacity(theme.brightness == Brightness.dark ? 0.12 : 0.18,
          )
        : theme.cardColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isHighlighted
              ? theme.colorScheme.secondary
              : theme.dividerColor,
          width: isHighlighted ? 1.5 : 1,
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isGold
                            ? Colors.amber.withOpacity(0.25)
                            : theme.colorScheme.primary
                                .withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        isGold
                            ? Icons.workspace_premium_rounded
                            : Icons.auto_awesome_rounded,
                        color: isGold
                            ? Colors.amber.shade700
                            : theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pkg.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            pkg.subtitle,
                            style: TextStyle(
                              color: theme.hintColor,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (pkg.compareAtPriceToman != null &&
                              pkg.compareAtPriceToman! > pkg.priceToman)
                            Text(
                              _formatToman(pkg.compareAtPriceToman!),
                              style: TextStyle(
                                color: theme.hintColor,
                                decoration: TextDecoration.lineThrough,
                                fontSize: 12,
                              ),
                            ),
                          Text(
                            _formatToman(pkg.priceToman),
                            style: TextStyle(
                              color: theme.colorScheme.secondary,
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                          ),
                          if (pkg.compareAtPriceToman != null &&
                              pkg.compareAtPriceToman! > pkg.priceToman)
                            Text(
                              'تخفیف: ${_formatToman(pkg.compareAtPriceToman! - pkg.priceToman)}',
                              style: TextStyle(
                                color: theme.colorScheme.secondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          if (unit != null)
                            Text(
                              pkg.credits != null
                                  ? 'حدود ${_formatToman(unit)} به‌ازای هر عیب‌یابی'
                                  : 'حدود ${_formatToman(unit)} در روز',
                              style: TextStyle(
                                color: theme.hintColor,
                                fontSize: 11,
                              ),
                            ),
                          if (pkg.bestCaseUnitPrice != null)
                            Text(
                              'هزینه تقریبی هر عیب‌یابی: حدود '
                              '${_formatToman(pkg.bestCaseUnitPrice!)} هر عیب‌یابی',
                              style: TextStyle(
                                color: theme.colorScheme.secondary
                                    .withOpacity(0.85),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...pkg.benefits.map(
                  (b) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_rounded,
                          size: 16,
                          color: theme.colorScheme.secondary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            b,
                            style: TextStyle(
                              fontSize: 13,
                              color: theme.colorScheme.onSurface
                                  .withOpacity(0.85),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          isGold ? Colors.amber.shade700 : theme.colorScheme.secondary,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: (isLoadingThis || isAnyLoading)
                        ? null
                        : () => _buyProduct(pkg.id),
                    child: isLoadingThis
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black54,
                            ),
                          )
                        : Text(
                            'خرید بسته',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                ),
              ],
            ),
          ),
          if (isHighlighted)
            Positioned(
              top: 0,
              left: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Text(
                  pkg.isBestValue ? 'به‌صرفه‌ترین' : 'محبوب‌ترین',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // فوتر
  // ---------------------------------------------------------------------------

  Widget _buildTrustFooter(ThemeData theme) {
    return Column(
      children: [
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_rounded, size: 14, color: theme.hintColor),
            const SizedBox(width: 6),
            Text(
              'پرداخت امن · فعال‌سازی آنی پس از پرداخت',
              style: TextStyle(color: theme.hintColor, fontSize: 12),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'عیب‌یابی‌ها ابزار کمکی هستند و جایگزین نظر مکانیک متخصص نیستند.',
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.hintColor, fontSize: 11),
        ),
      ],
    );
  }
}
