import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';

import 'brand.dart';

/// سازگاری با کد قدیمی — رنگ‌ها در [BrandColors] متمرکز شده‌اند
class AppColors {
  AppColors._();

  static const Color amber = BrandColors.gold;
  static const Color orange = BrandColors.orange;
  static const Color amberLight = BrandColors.goldLight;

  static const Color darkBackground = BrandColors.darkBackground;
  static const Color darkSurface = BrandColors.darkSurface;
  static const Color lightBackground = BrandColors.lightBackground;

  static const Color textOnDark = BrandColors.textOnDark;
  static const Color textOnLight = BrandColors.textOnLight;
  static const Color textSecondaryOnDark = BrandColors.textSecondaryOnDark;
  static const Color textSecondaryOnLight = BrandColors.textSecondaryOnLight;

  static const Color success = BrandColors.success;
  static const Color error = BrandColors.error;
}

/// تم‌های روشن و تاریک برنامه
class AppTheme {
  AppTheme._();

  static const _radius = 16.0;

  static final ThemeData darkTheme = _build(
    brightness: Brightness.dark,
    scaffold: BrandColors.darkBackground,
    surface: BrandColors.darkSurface,
    onSurface: BrandColors.textOnDark,
    divider: const Color(0xFF3D2A1C),
    inputFill: const Color(0xFF38241A),
  );

  static final ThemeData lightTheme = _build(
    brightness: Brightness.light,
    scaffold: BrandColors.lightBackground,
    surface: Colors.white,
    onSurface: BrandColors.textOnLight,
    divider: const Color(0xFFE8D5C4),
    inputFill: Colors.white,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color scaffold,
    required Color surface,
    required Color onSurface,
    required Color divider,
    required Color inputFill,
  }) {
    final isDark = brightness == Brightness.dark;
    final base = isDark ? ThemeData.dark() : ThemeData.light();
    final radius = BorderRadius.circular(_radius);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: scaffold,
      colorScheme: isDark
          ? const ColorScheme.dark(
              primary: BrandColors.orange,
              onPrimary: Colors.black,
              secondary: BrandColors.orange,
              onSecondary: Colors.black,
              tertiary: BrandColors.gold,
              surface: BrandColors.darkSurface,
              onSurface: BrandColors.textOnDark,
              error: BrandColors.error,
              onError: Colors.white,
            )
          : const ColorScheme.light(
              primary: BrandColors.orangeDeep,
              onPrimary: Colors.white,
              secondary: BrandColors.orangeDeep,
              onSecondary: Colors.white,
              tertiary: BrandColors.gold,
              surface: Colors.white,
              onSurface: BrandColors.textOnLight,
              error: BrandColors.error,
              onError: Colors.white,
            ),
      cardColor: surface,
      dividerColor: divider,
      textTheme: GoogleFonts.vazirmatnTextTheme(base.textTheme).apply(
        bodyColor: onSurface,
        displayColor: onSurface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardTheme(
        color: surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: divider),
        ),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: inputFill,
        border: OutlineInputBorder(
          borderRadius: radius,
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: radius,
          borderSide: const BorderSide(color: BrandColors.orange, width: 2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: BrandColors.orange,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: BrandColors.orange,
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onSurface,
          side: BorderSide(color: BrandColors.orange.withOpacity(0.55), width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: BrandColors.orange,
      ),
    );
  }
}
