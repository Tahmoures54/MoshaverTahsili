import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'education_app.dart';

/// گزارش خطاهای پیش‌بینی‌نشده.
///
/// developer.log در همه حالت‌های اجرا فراخوانی می‌شود؛
/// اما ذخیره‌سازی دائمی یا سرویس آنلاین گزارش خرابی نیست.
///
/// هنگام اضافه‌کردن گزارش آنلاین، اطلاعات حساس کاربر
/// باید پیش از ارسال از خطاها و لاگ‌ها حذف شوند.
void _reportError(
  Object error,
  StackTrace stackTrace, {
  required String source,
  bool printDebug = true,
}) {
  developer.log(
    'Unhandled error in $source',
    name: 'moshaver_tahsili',
    level: 1000,
    error: error,
    stackTrace: stackTrace,
  );

  if (kDebugMode && printDebug) {
    debugPrint('moshaver_tahsili [$source]: $error');
    debugPrintStack(stackTrace: stackTrace);
  }
}

void main() {
  runZonedGuarded<void>(
    () {
      // Binding و runApp باید در یک Zone اجرا شوند.
      WidgetsFlutterBinding.ensureInitialized();

      // خطاهایی که فریم‌ورک Flutter دریافت می‌کند.
      FlutterError.onError = (FlutterErrorDetails details) {
        // حفظ نمایش استاندارد خطا توسط Flutter.
        FlutterError.presentError(details);

        _reportError(
          details.exception,
          details.stack ?? StackTrace.current,
          source: 'Flutter framework',

          // presentError خروجی استاندارد را نمایش داده است؛
          // چاپ مجدد پیام و stack trace لازم نیست.
          printDebug: false,
        );
      };

      // خطاهای مدیریت‌نشده‌ای که به Flutter engine می‌رسند.
      PlatformDispatcher.instance.onError =
          (Object error, StackTrace stackTrace) {
            _reportError(error, stackTrace, source: 'Platform dispatcher');

            // جلوگیری از گزارش fallback موتور.
            // این مقدار به معنای بازیابی برنامه پس از خطا نیست.
            return true;
          };

      runApp(const EducationApp());
    },

    // خطاهای مدیریت‌نشده در Zone برنامه.
    (Object error, StackTrace stackTrace) {
      _reportError(error, stackTrace, source: 'Application zone');
    },
  );
}
