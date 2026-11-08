import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/brand.dart';

/// نشان اعتماد اینماد + لینک به سایت رسمی
/// تصویر از پروکسی هم‌دامنه لود می‌شود تا باکس سفید (بلاک هات‌لینک) نماند.
class EnamadBadge extends StatelessWidget {
  final bool compact;

  const EnamadBadge({super.key, this.compact = false});

  static String get _proxyLogo => '${Brand.websiteUrl}/api/enamad-logo';

  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = compact ? 72.0 : 100.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          elevation: 4,
          shadowColor: Colors.black54,
          child: InkWell(
            onTap: () => _open(Brand.enamadProfileUrl),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: size + 20,
              height: size + 20,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFFB300), width: 1.5),
              ),
              child: Image.network(
                _proxyLogo,
                width: size,
                height: size,
                fit: BoxFit.contain,
                headers: {
                  'Referer': '${Brand.websiteUrl}/',
                  'Accept': 'image/*,*/*',
                },
                errorBuilder: (_, __, ___) => Image.network(
                  Brand.enamadLogoUrl,
                  width: size,
                  height: size,
                  fit: BoxFit.contain,
                  headers: {
                    'Referer': '${Brand.websiteUrl}/',
                  },
                  errorBuilder: (_, __, ___) => Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.verified_user_rounded,
                          color: theme.colorScheme.primary,
                          size: size * 0.35,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'اینماد',
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return SizedBox(
                    width: size,
                    height: size,
                    child: const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => _open(Brand.websiteUrl),
          icon: const Icon(Icons.language_rounded, size: 18),
          label: const Text('smart-mec.ir'),
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.secondary,
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Text(
          'نماد اعتماد الکترونیکی',
          style: TextStyle(
            fontSize: 11,
            color: theme.hintColor,
          ),
        ),
      ],
    );
  }
}
