import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ── تنظیمات زبان ──
// ─────────────────────────────────────────────────────────────────────────────
class LocaleConfig {
  LocaleConfig._();

  static const List<Locale> supportedLocales = [
    Locale('fa', 'IR'), // فارسی
    Locale('en', 'US'), // انگلیسی
  ];

  /// برای MaterialApp.supportedLocales
  static List<Locale> get flutterLocales => supportedLocales;

  static const Locale defaultLocale = Locale('fa', 'IR');

  static TextDirection getTextDirection(Locale locale) {
    return locale.languageCode == 'fa' || locale.languageCode == 'ar'
        ? TextDirection.rtl
        : TextDirection.ltr;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ── Provider زبان ──
// ─────────────────────────────────────────────────────────────────────────────
class LocaleProvider extends ChangeNotifier {
  static const _key = 'locale_language_code';

  Locale _locale;
  final SharedPreferences _prefs;

  LocaleProvider._(this._locale, this._prefs);

  /// ساخت با بارگذاری از SharedPreferences
  static Future<LocaleProvider> create() async {
    final prefs = await SharedPreferences.getInstance();
    final langCode = prefs.getString(_key);

    Locale locale = LocaleConfig.defaultLocale;
    if (langCode != null) {
      final found = LocaleConfig.supportedLocales.firstWhere(
        (l) => l.languageCode == langCode,
        orElse: () => LocaleConfig.defaultLocale,
      );
      locale = found;
    }

    return LocaleProvider._(locale, prefs);
  }

  // ─────────────────────────────────────────
  // ── Getters ──
  // ─────────────────────────────────────────

  Locale get locale => _locale;

  TextDirection get textDirection =>
      LocaleConfig.getTextDirection(_locale);

  bool get isRTL => textDirection == TextDirection.rtl;

  bool get isFarsi => _locale.languageCode == 'fa';

  // ─────────────────────────────────────────
  // ── تغییر زبان ──
  // ─────────────────────────────────────────

  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) return;

    final isSupported = LocaleConfig.supportedLocales.contains(locale);
    if (!isSupported) {
      debugPrint('[LocaleProvider] زبان پشتیبانی نمی‌شود: $locale');
      return;
    }

    _locale = locale;
    await _prefs.setString(_key, locale.languageCode);
    notifyListeners();
  }

  Future<void> setFarsi() => setLocale(const Locale('fa', 'IR'));
  Future<void> setEnglish() => setLocale(const Locale('en', 'US'));

  Future<void> toggleLocale() async {
    if (isFarsi) {
      await setEnglish();
    } else {
      await setFarsi();
    }
  }

  @override
  String toString() => 'LocaleProvider(locale: $_locale)';
}
