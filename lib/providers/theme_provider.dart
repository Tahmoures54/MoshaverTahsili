import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const _key = 'theme_mode';

  ThemeMode _themeMode;
  final SharedPreferences _prefs; // ✅ نگه داشتن نمونه برای استفاده‌های بعدی

  ThemeProvider._(this._themeMode, this._prefs);

  /// ساخت با بارگذاری از SharedPreferences
  static Future<ThemeProvider> create() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);

    // ✅ پارس خودکار با استفاده از نام ThemeMode
    final mode = ThemeMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => ThemeMode.light, // تم پیش‌فرض روشن و آرام‌تر
    );

    return ThemeProvider._(mode, prefs);
  }

  // ─────────────────────────────────────────
  // ── Getters ──
  // ─────────────────────────────────────────

  ThemeMode get themeMode => _themeMode;
  bool get isDark => _themeMode == ThemeMode.dark;
  bool get isLight => _themeMode == ThemeMode.light;
  bool get isSystem => _themeMode == ThemeMode.system;

  // ─────────────────────────────────────────
  // ── تغییر تم ──
  // ─────────────────────────────────────────

  Future<void> setTheme(ThemeMode mode) async {
    if (_themeMode == mode) return;
    
    _themeMode = mode;
    notifyListeners();

    // ✅ استفاده از نمونه ذخیره شده (سریع‌تر و بدون نیاز به await مجدد)
    try {
      await _prefs.setString(_key, mode.name);
    } catch (e) {
      debugPrint('[ThemeProvider] خطا در ذخیره تم: $e');
    }
  }

  void toggleTheme() {
    if (isSystem) {
      unawaited(setTheme(ThemeMode.dark));
    } else {
      unawaited(setTheme(isDark ? ThemeMode.light : ThemeMode.dark));
    }
  }

  void setDarkTheme() => setTheme(ThemeMode.dark);
  void setLightTheme() => setTheme(ThemeMode.light);
  void setSystemTheme() => setTheme(ThemeMode.system);
}
