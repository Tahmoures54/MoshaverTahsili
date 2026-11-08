import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'education_app.dart';
import 'education/education_store.dart';

void main() async {
  // ۱) مقداردهی اولیه Flutter
  WidgetsFlutterBinding.ensureInitialized();

  // ۲) قفل جهت عمودی (جلوگیری از به‌هم‌ریختگی RTL)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // ۳) هماهنگ‌سازی رنگ Status Bar با رنگ برند
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0xFF17324D), // _navy
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF17324D),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // ۴) ثبت خطایاب سراسری (برای گزارش‌دهی در release)
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('❌ خطای Flutter: ${details.exceptionAsString()}');
  };

  // ۵) اجرای اپ با Provider سراسری
  runApp(
    ChangeNotifierProvider(
      create: (_) => EducationStore(),
      child: const EducationApp(),
    ),
  );
}
