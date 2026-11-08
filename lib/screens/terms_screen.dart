import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants.dart';
import '../legal/terms_of_use.dart';
import '../theme/brand.dart';
import '../widgets/brand_logo.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  // ---------------------------------------------------------------------------
  // متدهای کمکی
  // ---------------------------------------------------------------------------

  void _showSnack(BuildContext context, String message, {Color? color}) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color ?? Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _mail(BuildContext context) async {
    final uri = Uri(
      scheme: 'mailto',
      path: Constants.supportEmail,
      queryParameters: {
        'subject': 'قوانین استفاده - ${Constants.appName}',
      },
    );

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return;
      }
    } catch (e) {
      debugPrint('[TermsScreen] mail launch failed: $e');
    }

    // Fallback: کپی ایمیل
    try {
      await Clipboard.setData(
        const ClipboardData(text: Constants.supportEmail),
      );
      _showSnack(context, 'ایمیل پشتیبانی کپی شد');
    } catch (e) {
      debugPrint('[TermsScreen] clipboard fallback failed: $e');
      _showSnack(
        context,
        'امکان باز کردن ایمیل یا کپی نیست.',
        color: Colors.redAccent,
      );
    }
  }

  Future<void> _copyFullText(BuildContext context) async {
    try {
      await Clipboard.setData(ClipboardData(text: _fullText()));
      _showSnack(context, 'متن قوانین کپی شد');
    } catch (e) {
      debugPrint('[TermsScreen] copy failed: $e');
      _showSnack(
        context,
        'کپی کردن ناموفق بود',
        color: Colors.redAccent,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final orange = theme.colorScheme.primary;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text(
          TermsOfUse.title,
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            tooltip: 'کپی',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () => _copyFullText(context),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _buildHeaderCard(theme, orange),
            const SizedBox(height: 16),
            ...TermsOfUse.sections.map(
              (s) => _buildSectionCard(s, theme, orange),
            ),
            _buildContactCard(context, theme, orange),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ویجت‌ها
  // ---------------------------------------------------------------------------

  Widget _buildHeaderCard(ThemeData theme, Color orange) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            orange.withOpacity(0.28),
            theme.cardColor,
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: orange.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          const BrandLogo(size: 56, showGlow: true),
          const SizedBox(height: 12),
          Text(
            Brand.nameFa,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            TermsOfUse.analysisDisclaimer,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'آخرین به‌روزرسانی: ${TermsOfUse.updatedAt}',
            style: TextStyle(fontSize: 12, color: theme.hintColor),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard(
    TermsSection s,
    ThemeData theme,
    Color orange,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardColor.withOpacity(0.92),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: orange.withOpacity(0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.title,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: orange,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              s.body,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.7,
                color: theme.colorScheme.onSurface.withOpacity(0.9),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactCard(
    BuildContext context,
    ThemeData theme,
    Color orange,
  ) {
    return InkWell(
      onTap: () => _mail(context),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardColor.withOpacity(0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          children: [
            Icon(Icons.email_rounded, color: orange),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'سوال حقوقی یا حذف حساب',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
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
            Icon(Icons.chevron_left_rounded, color: theme.hintColor),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // متن کامل برای کپی
  // ---------------------------------------------------------------------------

  static String _fullText() {
    final buf = StringBuffer()
      ..writeln('${TermsOfUse.title} — ${Brand.nameFa}')
      ..writeln('آخرین به‌روزرسانی: ${TermsOfUse.updatedAt}')
      ..writeln()
      ..writeln(TermsOfUse.analysisDisclaimer)
      ..writeln();
    for (final s in TermsOfUse.sections) {
      buf
        ..writeln(s.title)
        ..writeln(s.body)
        ..writeln();
    }
    buf.writeln('پشتیبانی: ${Constants.supportEmail}');
    return buf.toString();
  }
}
