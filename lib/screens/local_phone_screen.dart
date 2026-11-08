import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../widgets/brand_logo.dart';

class _PhoneDigitFormatter extends TextInputFormatter {
  const _PhoneDigitFormatter();

  static const _digits = <String, String>{
    '۰': '0', '۱': '1', '۲': '2', '۳': '3', '۴': '4',
    '۵': '5', '۶': '6', '۷': '7', '۸': '8', '۹': '9',
    '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4',
    '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
  };

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final out = StringBuffer();
    for (final ch in newValue.text.split('')) {
      final digit = _digits[ch];
      if (digit != null) {
        out.write(digit);
      } else if (RegExp(r'[0-9]').hasMatch(ch)) {
        out.write(ch);
      }
    }
    final text = out.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class LocalPhoneScreen extends StatefulWidget {
  const LocalPhoneScreen({super.key});

  @override
  State<LocalPhoneScreen> createState() => _LocalPhoneScreenState();
}

class _LocalPhoneScreenState extends State<LocalPhoneScreen> {
  final _phone = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final value = _phone.text.trim();
    if (!RegExp(r'^09\d{9}$').hasMatch(value)) {
      setState(() => _error = 'شماره موبایل معتبر وارد کنید؛ مانند 09123456789');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<AuthProvider>().saveLocalPhone(value);
    } catch (e) {
      if (mounted) setState(() => _error = 'ذخیره شماره انجام نشد. دوباره تلاش کنید.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                elevation: 0,
                color: theme.colorScheme.surface.withOpacity(0.96),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                  side: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const BrandLogo(size: 92, showGlow: true),
                      const SizedBox(height: 18),
                      Text(
                        'شروع استفاده از مکانیک هوشمند',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'شماره موبایل را برای ذخیره پروفایل روی همین گوشی وارد کنید. برای شروع، کد پیامکی لازم نیست.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.7,
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.center,
                        maxLength: 11,
                        inputFormatters: [
                          const _PhoneDigitFormatter(),
                          LengthLimitingTextInputFormatter(11),
                        ],
                        decoration: InputDecoration(
                          labelText: 'شماره موبایل',
                          hintText: '09123456789',
                          prefixIcon: const Icon(Icons.phone_android_rounded),
                          errorText: _error,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onSubmitted: (_) => _continue(),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: _saving ? null : _continue,
                          icon: _saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.arrow_forward_rounded),
                          label: Text(_saving ? 'در حال ذخیره...' : 'شروع عیب‌یابی'),
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'شماره و تاریخچه عیب‌یابی روی گوشی ذخیره می‌شوند.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
