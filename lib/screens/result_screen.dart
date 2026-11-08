import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/share_service.dart';

/// صفحهٔ خوانا و سبک برای نمایش پاسخ هوش مصنوعی.
class ResultScreen extends StatelessWidget {
  final String? resultText;

  const ResultScreen({super.key, this.resultText});

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('پاسخ کپی شد'),
      ),
    );
  }

  Future<void> _share(BuildContext context, String text) async {
    final auth = context.read<AuthProvider>();
    await ShareService.shareDiagnosis(
      result: text,
      referralCode: auth.referralCode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final text = resultText?.trim() ?? '';
    final isDark = theme.brightness == Brightness.dark;

    final markdownStyle = MarkdownStyleSheet.fromTheme(theme).copyWith(
      p: theme.textTheme.bodyLarge?.copyWith(height: 1.85, fontSize: 15),
      h1: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        height: 1.45,
        color: colors.primary,
      ),
      h2: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        height: 1.5,
        color: colors.primary,
      ),
      h3: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
        height: 1.5,
      ),
      strong: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
      listBullet: theme.textTheme.bodyLarge?.copyWith(color: colors.primary),
      blockquote: theme.textTheme.bodyMedium?.copyWith(height: 1.7),
      blockquoteDecoration: BoxDecoration(
        color: colors.primary.withOpacity(isDark ? 0.12 : 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border(
          right: BorderSide(color: colors.primary, width: 3),
        ),
      ),
      blockquotePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      codeblockDecoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      tableBorder: TableBorder.all(
        color: colors.outlineVariant,
        borderRadius: BorderRadius.circular(8),
      ),
      tableCellsPadding: const EdgeInsets.all(8),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('پاسخ مکانیک هوشمند'),
        centerTitle: false,
        actions: [
          if (text.isNotEmpty)
            IconButton(
              tooltip: 'کپی متن پاسخ',
              onPressed: () => _copy(context, text),
              icon: const Icon(Icons.copy_all_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: text.isEmpty
            ? _EmptyResponse(colors: colors)
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topRight,
                              end: Alignment.bottomLeft,
                              colors: [
                                colors.primary.withOpacity(isDark ? 0.24 : 0.12),
                                colors.secondary.withOpacity(isDark ? 0.12 : 0.06),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: colors.primary.withOpacity(0.15),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: colors.primary,
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                child: Icon(
                                  Icons.handyman_rounded,
                                  color: colors.onPrimary,
                                  size: 25,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'بررسی هوشمند خودرو',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'پاسخ اختصاصی بر اساس پیام شما',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: colors.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.auto_awesome_rounded, color: colors.primary),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: colors.outlineVariant),
                            boxShadow: [
                              BoxShadow(
                                color: colors.shadow.withOpacity(isDark ? 0.04 : 0.035),
                                blurRadius: 16,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: MarkdownBody(
                            data: text,
                            selectable: true,
                            styleSheet: markdownStyle,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 17,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                'این پاسخ راهنمای اولیه است؛ برای موارد خطرناک یا تشخیص قطعی، بررسی تعمیرکار ضروری است.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  height: 1.6,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    decoration: BoxDecoration(
                      color: colors.surface,
                      border: Border(
                        top: BorderSide(color: colors.outlineVariant),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: colors.shadow.withOpacity(0.04),
                          blurRadius: 12,
                          offset: const Offset(0, -3),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _copy(context, text),
                            icon: const Icon(Icons.copy_rounded, size: 19),
                            label: const Text('کپی پاسخ'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            onPressed: () => _share(context, text),
                            icon: const Icon(Icons.share_rounded, size: 20),
                            label: const Text(
                              'اشتراک‌گذاری پاسخ',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _EmptyResponse extends StatelessWidget {
  final ColorScheme colors;

  const _EmptyResponse({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded, size: 54, color: colors.outline),
            const SizedBox(height: 14),
            Text(
              'پاسخی برای نمایش وجود ندارد',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'به صفحهٔ قبل برگردید و دوباره پیام خود را ارسال کنید.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.6,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
