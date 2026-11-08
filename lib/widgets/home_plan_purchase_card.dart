import 'package:flutter/material.dart';

import '../theme/brand.dart';

class HomePlanPurchaseCard extends StatelessWidget {
  final VoidCallback onTap;
  final int credits;
  final bool isGoldenActive;

  const HomePlanPurchaseCard({
    super.key,
    required this.onTap,
    required this.credits,
    required this.isGoldenActive,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.secondary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
              colors: [
                const Color(0xFF2A1A0E),
                theme.cardColor,
              ],
            ),
            border: Border.all(color: accent.withOpacity(0.22)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.10),
                blurRadius: 16,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 12, 13),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    color: BrandColors.gold.withOpacity(0.13),
                    border: Border.all(color: BrandColors.gold.withOpacity(0.22)),
                  ),
                  child: Icon(
                    isGoldenActive
                        ? Icons.workspace_premium_rounded
                        : Icons.auto_awesome_rounded,
                    color: BrandColors.gold,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isGoldenActive ? 'اشتراک طلایی شما فعال است' : 'برای عیب‌یابی بیشتر آماده‌ای؟',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isGoldenActive
                            ? 'اعتبار فعلی: $credits • مدیریت پلن و اعتبار'
                            : 'پلن و اعتبار موردنیازت را انتخاب کن',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.4,
                          color: theme.textTheme.bodySmall?.color?.withOpacity(0.68),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isGoldenActive ? 'مدیریت' : 'خرید پلن',
                    style: TextStyle(
                      color: theme.colorScheme.onSecondary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
