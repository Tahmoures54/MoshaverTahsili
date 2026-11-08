import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

enum AppEnvironment {
  development,
  staging,
  production;

  bool get isDev => this == development;
  bool get isStaging => this == staging;
  bool get isProd => this == production;

  String get label => switch (this) {
        AppEnvironment.development => 'Development',
        AppEnvironment.staging => 'Staging',
        AppEnvironment.production => 'Production',
      };
}

class EnvironmentConfig {
  final AppEnvironment environment;
  final String baseUrl;
  final bool enableLogging;
  final bool enableCrashReporting;

  const EnvironmentConfig({
    required this.environment,
    required this.baseUrl,
    this.enableLogging = false,
    this.enableCrashReporting = true,
  });

  /// Official Smart Mechanic API root.
  static const String _defaultBaseUrl = 'https://smart-mec.ir/api';

  static String get _baseUrlFromEnv {
    try {
      final v = dotenv.env['API_BASE_URL']?.trim();
      if (v != null && v.isNotEmpty) return v.replaceAll(RegExp(r'/+$'), '');
    } catch (_) {}
    return _defaultBaseUrl;
  }

  static bool get _loggingFromEnv {
    try {
      final v = dotenv.env['ENABLE_API_LOGGING']?.trim().toLowerCase();
      if (v == 'true' || v == '1') return true;
      if (v == 'false' || v == '0') return false;
    } catch (_) {}
    return kDebugMode;
  }

  static EnvironmentConfig get development => EnvironmentConfig(
        environment: AppEnvironment.development,
        baseUrl: _baseUrlFromEnv,
        enableLogging: true,
        enableCrashReporting: false,
      );

  static EnvironmentConfig get staging => EnvironmentConfig(
        environment: AppEnvironment.staging,
        baseUrl: _baseUrlFromEnv,
        enableLogging: true,
        enableCrashReporting: true,
      );

  static EnvironmentConfig get production => EnvironmentConfig(
        environment: AppEnvironment.production,
        baseUrl: _baseUrlFromEnv,
        enableLogging: _loggingFromEnv,
        enableCrashReporting: true,
      );

  static EnvironmentConfig get current {
    if (kDebugMode) return development;
    if (kProfileMode) return staging;
    return production;
  }
}

class Constants {
  Constants._();

  static EnvironmentConfig get env => EnvironmentConfig.current;

  /// The backend currently serves its canonical routes directly under /api.
  /// Keeping this configurable allows future versioned routes without making
  /// production authentication depend on a rewrite layer.
  static String get _apiVersion {
    try {
      final v = dotenv.env['API_VERSION']?.trim();
      if (v != null && v.isNotEmpty) return v.replaceAll(RegExp(r'^/+|/+$'), '');
    } catch (_) {}
    return '';
  }

  static String get baseUrl => env.baseUrl;
  static String get apiUrl =>
      _apiVersion.isEmpty ? baseUrl : '$baseUrl/$_apiVersion';

  // Diagnose
  static String get diagnose => '$apiUrl/diagnose';
  static String get diagnoseHistory => '$apiUrl/diagnose';
  static String deleteDiagnose(String id) => '$apiUrl/diagnose/$id';


  // Static files are served from the site origin, not under /api.
  static String get carsJson {
    final uri = Uri.parse(baseUrl);
    final origin = uri
        .replace(path: '', query: null)
        .toString()
        .replaceAll(RegExp(r'/+$'), '');
    return '$origin/cars.json';
  }

  static String get health => '$apiUrl/health';

  static const String enamadProfileUrl =
      'https://trustseal.enamad.ir/?id=7731207&Code=Q14UpKWtFFDXzZarnOhA5dzChbURT0br';

  static const Duration defaultTimeout = Duration(seconds: 20);
  /// هم‌تراز با maxDuration / AI_TIMEOUT_MS بک‌اند (thinking).
  static const Duration diagnoseTimeout = Duration(seconds: 100);
  static const Duration longPollTimeout = Duration(minutes: 2);

  static const Duration carsCacheDuration = Duration(hours: 6);
  static const Duration profileCacheDuration = Duration(seconds: 30);

  static const String appName = 'مکانیک هوشمند';
  static const String appNameEn = 'Smart Mechanic';
  static const String appTagline = 'بزرگترین بانک اطلاعات فنی خودرویی کشور';
  static const String appVersion = '1.3.4';
  static const int appBuildNumber = 10;
  static const String packageName = 'ir.smartmec.app';
  static const String supportEmail = 'support@smart-mec.ir';

  static const String keyJwtToken = 'jwt_token';
  static const String keySelectedLocale = 'selected_locale';
  static const String keyLastCarId = 'last_car_id';
  static const String keyLastCustomCar = 'last_custom_car_name';
  static const String keyLastYear = 'last_year';
  static const String keyThemeMode = 'theme_mode';

  static const String boxDiagnostics = 'diagnostics';
  static const String boxHistory = 'history';
  static const String boxUserProfile = 'user_profile';

  /// هم‌تراز با سقف بک‌اند (validateDescription ≤ 2000) — متن کاربر کوتاه نشود.
  static const int maxDescriptionLength = 2000;
  static const int minDescriptionLength = 5;
  static const int maxChatMessages = 50;
  static const int otpLength = 6;
  static const int phoneLength = 11;

  static const bool featureAudioDiagnosis = true;
  static const bool featureReferral = true;
  static const bool featureWithdraw = true;
  static const bool featureObdDiagnosis = false;

  static const Duration minRequestInterval = Duration(milliseconds: 500);
  static const Duration otpResendCooldown = Duration(seconds: 60);

  static void printInfo() {
    if (!env.enableLogging) return;
    debugPrint('════════════════════════════════');
    debugPrint('🚗 $appName v$appVersion+$appBuildNumber');
    debugPrint('🌐 Env: ${env.environment.label}');
    debugPrint('🔗 BaseUrl: $baseUrl');
    debugPrint('🔗 ApiUrl: $apiUrl');
    debugPrint('📝 Logging: ${env.enableLogging}');
    debugPrint('════════════════════════════════');
  }
}

/// ─── سیاست «پاسخ مستقیم» (حذف دورهای پرسش‌وپاسخ) ─────────────────────
class DiagnosisPolicy {
  DiagnosisPolicy._();

  /// سقف خروجی به بک‌اند — برابر validateDescription بک‌اند؛ متن کوتاه نشود.
  static const int maxOutboundLength = 2000;

  static const String requestDirective =
      '[دستور اپلیکیشن: هیچ سؤالی نپرس؛ همین حالا یک پاسخ تشخیصی کامل به سبک '
      'مقاله بده: ۲ تا ۴ علت احتمالی را با توضیح کوتاه و نحوهٔ بررسی فهرست کن، '
      'ابهام‌ها را با سناریوی «اگر…» پوشش بده و در پایان با یک جملهٔ کوتاه '
      'کاربر را به ادامهٔ گفتگو تشویق کن.]';

  static const String encouragementText =
      'هنوز سؤال یا جزئیاتی برایت مبهم مانده؟ همان‌طور که هست بنویس تا دقیق‌تر بررسی کنیم.';

  static const List<String> followUpSuggestions = [
    'هزینهٔ تعمیرش تقریباً چقدر در می‌آید؟',
    'خودم چطور می‌توانم این مشکل را بررسی کنم؟',
    'تا زمان تعمیر، رانندگی کردن خطرناک است؟',
  ];

  static final RegExp _directivePattern =
      RegExp(r'\[دستور اپلیکیشن:[^\]]*\]');

  /// افزودن دستور سیاست؛ اگر جا نبود، متن کاربر کامل می‌ماند (کوتاه نمی‌شود).
  static String withDirective(String text) {
    final trimmed = text.trim();
    final combined =
        trimmed.isEmpty ? requestDirective : '$trimmed\n\n$requestDirective';
    if (combined.length > maxOutboundLength) {
      // Prefer full user text over the directive — never truncate the problem description.
      return trimmed.length > maxOutboundLength
          ? trimmed.substring(0, maxOutboundLength)
          : trimmed;
    }
    return combined;
  }

  static String stripDirective(String text) =>
      text.replaceFirst(_directivePattern, '').trim();
}
