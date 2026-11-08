import 'package:flutter/services.dart';

const String _persianDigits = '۰۱۲۳۴۵۶۷۸۹';
const String _arabicDigits = '٠١٢٣٤٥٦٧٨٩';
const String _latinDigits = '0123456789';

/// ارقام فارسی/عربی را به لاتین تبدیل می‌کند و جداکننده‌های رایج را حذف می‌کند.
///
/// چرا لازم است: int.tryParse در Dart فقط ارقام ASCII را می‌شناسد، پس
/// int.tryParse('۱۴۰۲') برابر null است. بدون این نرمال‌سازی، کاربری که با
/// کیبورد فارسی سال را وارد می‌کند هرگز نمی‌تواند از فرم عبور کند.
String normalizeDigits(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);

    final persianIndex = _persianDigits.indexOf(ch);
    if (persianIndex != -1) {
      buffer.write(persianIndex);
      continue;
    }

    final arabicIndex = _arabicDigits.indexOf(ch);
    if (arabicIndex != -1) {
      buffer.write(arabicIndex);
      continue;
    }

    // جداکننده‌های هزارگان و نیم‌فاصله را نادیده بگیر
    if (ch == '٬' || ch == ',' || ch == '\u200c') continue;

    buffer.write(ch);
  }
  return buffer.toString();
}

/// ارقام لاتین را برای نمایش به فارسی تبدیل می‌کند.
String toPersianDigits(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    final index = _latinDigits.indexOf(ch);
    buffer.write(index == -1 ? ch : _persianDigits[index]);
  }
  return buffer.toString();
}

/// نسخهٔ مقاوم int.tryParse که ارقام فارسی/عربی را هم می‌پذیرد.
int? parseFlexibleInt(String input) => int.tryParse(normalizeDigits(input).trim());

/// اجازه می‌دهد کاربر با هر سه نوع رقم تایپ کند، ولی چیز دیگری وارد نشود.
class MultiScriptDigitsFormatter extends TextInputFormatter {
  const MultiScriptDigitsFormatter({this.maxLength});
  final int? maxLength;

  static final RegExp _allowed = RegExp(r'[0-9۰-۹٠-٩]');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final filtered = newValue.text.split('').where((c) => _allowed.hasMatch(c)).join();
    final limited =
        (maxLength != null && filtered.length > maxLength!) ? filtered.substring(0, maxLength!) : filtered;

    if (limited == newValue.text) return newValue;
    return TextEditingValue(
      text: limited,
      selection: TextSelection.collapsed(offset: limited.length.clamp(0, limited.length)),
    );
  }
}
