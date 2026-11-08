import 'package:flutter/material.dart';

import '../../providers/auth_provider.dart';

class CreditBadge extends StatelessWidget {
  const CreditBadge({super.key, required this.auth});
  final AuthProvider auth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (auth.isGoldenActive) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: Colors.amber.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
        child: const Text('طلایی', style: TextStyle(fontSize: 12, color: Colors.amber)),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondary.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('اعتبار: ${auth.credits}',
          style: TextStyle(fontSize: 12, color: theme.colorScheme.secondary)),
    );
  }
}

class TypingBanner extends StatelessWidget {
  const TypingBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.secondary.withOpacity(0.08),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.secondary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text('لطفاً صبر کنید — هوش مصنوعی در حال بررسی است…',
                style: TextStyle(fontSize: 12, color: theme.colorScheme.secondary)),
          ),
        ],
      ),
    );
  }
}

/// وقتی اعتبار کافی نیست، به‌جای فقط یک پیام متنی، مستقیم CTA به فروشگاه بده.
class InsufficientCreditBanner extends StatelessWidget {
  const InsufficientCreditBanner({super.key, required this.onBuy});
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet_outlined, color: Colors.redAccent, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('اعتبار شما کافی نیست.', style: TextStyle(fontSize: 13, color: Colors.redAccent)),
          ),
          TextButton(
            onPressed: onBuy,
            child: const Text('خرید بسته', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
