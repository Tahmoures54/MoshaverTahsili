import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// انواع اعلان — برای مدیریت و لغو جداگانه
enum AppNotificationType {
  lowCredits(1001),
  goldenExpiring(1002),
  goldenExpiringThreeDays(10021),
  goldenExpiringOneDay(10022),
  checkupReminder(1003),
  referralMilestone(1004),
  welcome(1005),
  general(1000);

  const AppNotificationType(this.id);
  final int id;
}

/// کلیدهای تنظیمات کاربر
class NotificationPrefs {
  static const enabled = 'notif_enabled';
  static const lowCredits = 'notif_low_credits';
  static const golden = 'notif_golden';
  static const checkup = 'notif_checkup';
  static const referral = 'notif_referral';
  static const checkupDayOfWeek = 'notif_checkup_dow'; // 1=Mon … 7=Sun
  static const checkupHour = 'notif_checkup_hour';
}

/// سرویس نوتیفیکیشن محلی
///
/// قابلیت‌ها:
/// - درخواست مجوز (Android 13+ / iOS)
/// - اعلان فوری
/// - زمان‌بندی (چکاپ دوره‌ای، انقضای طلایی)
/// - یادآوری ملایم اعتبار کم (هم‌راستا با تحلیل رفتار کاربر)
/// - تنظیمات on/off برای هر نوع
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  SharedPreferences? _prefs;

  int? _pendingCredits;
  bool? _pendingGoldenActive;
  DateTime? _pendingGoldenExpiry;
  int _pendingEarnings = 0;
  int _pendingMinWithdrawal = 50000;
  bool _hasPendingProfileSync = false;

  static const _channelId = 'smart_mec_main';
  static const _channelName = 'اعلان‌های مکانیک هوشمند';
  static const _channelDesc = 'یادآوری اعتبار، اشتراک و چکاپ خودرو';

  /// مقداردهی اولیه — از main() صدا زده شود
  Future<void> init() async {
    if (_initialized) return;

    _prefs = await SharedPreferences.getInstance();

    // پیش‌فرض: همه فعال
    _prefs!.setBool(NotificationPrefs.enabled, _prefs!.getBool(NotificationPrefs.enabled) ?? true);
    _prefs!.setBool(NotificationPrefs.lowCredits, _prefs!.getBool(NotificationPrefs.lowCredits) ?? true);
    _prefs!.setBool(NotificationPrefs.golden, _prefs!.getBool(NotificationPrefs.golden) ?? true);
    _prefs!.setBool(NotificationPrefs.checkup, _prefs!.getBool(NotificationPrefs.checkup) ?? true);
    _prefs!.setBool(NotificationPrefs.referral, _prefs!.getBool(NotificationPrefs.referral) ?? true);

    tz.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      // fallback ایران
      try {
        tz.setLocalLocation(tz.getLocation('Asia/Tehran'));
      } catch (e) {
        debugPrint('[NotificationService] timezone fallback failed: $e');
      }
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onTap,
    );

    // کانال اندروید
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.defaultImportance,
      ),
    );

    _initialized = true;
    debugPrint('[NotificationService] initialized');
    if (_hasPendingProfileSync && notificationsEnabled) {
      final credits = _pendingCredits ?? 0;
      final goldenActive = _pendingGoldenActive ?? false;
      final goldenExpiry = _pendingGoldenExpiry;
      final earnings = _pendingEarnings;
      final minWithdrawal = _pendingMinWithdrawal;
      _hasPendingProfileSync = false;
      await syncFromProfile(credits: credits, isGoldenActive: goldenActive, goldenExpiry: goldenExpiry, earnings: earnings, minWithdrawal: minWithdrawal);
    }
  }

  void _onTap(NotificationResponse response) {
    debugPrint('[NotificationService] tapped: ${response.payload}');
    // payload می‌تواند برای deep-link استفاده شود: shop | home | history
  }

  // ─── مجوزها ─────────────────────────────────────────────────────────────

  Future<bool> requestPermission() async {
    await init();
    if (kIsWeb) return false;

    if (Platform.isAndroid) {
      final status = await Permission.notification.request();
      if (status.isGranted) return true;
      // Android 13+
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted == true;
    }

    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      final granted = await ios?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted == true;
    }

    return true;
  }

  Future<bool> get isPermissionGranted async {
    if (kIsWeb) return false;
    if (Platform.isAndroid) {
      return Permission.notification.isGranted;
    }
    return true;
  }

  // ─── تنظیمات ────────────────────────────────────────────────────────────

  bool get notificationsEnabled =>
      _prefs?.getBool(NotificationPrefs.enabled) ?? true;

  Future<void> setNotificationsEnabled(bool value) async {
    await init();
    await _prefs?.setBool(NotificationPrefs.enabled, value);
    if (!value) await cancelAll();
  }

  bool isTypeEnabled(String key) => _prefs?.getBool(key) ?? true;

  Future<void> setTypeEnabled(String key, bool value) async {
    await init();
    await _prefs?.setBool(key, value);
    if (!value) {
      if (key == NotificationPrefs.lowCredits) {
        await cancel(AppNotificationType.lowCredits);
      } else if (key == NotificationPrefs.golden) {
        await _cancelGoldenExpiry();
      } else if (key == NotificationPrefs.checkup) {
        await cancel(AppNotificationType.checkupReminder);
      } else if (key == NotificationPrefs.referral) {
        await cancel(AppNotificationType.referralMilestone);
      }
    }
  }

  // ─── اعلان فوری ─────────────────────────────────────────────────────────

  Future<void> show({
    required AppNotificationType type,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized || !notificationsEnabled) return;

    await _plugin.show(
      type.id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: '@mipmap/ic_launcher',
          styleInformation: BigTextStyleInformation(body),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payload,
    );
  }

  // ─── زمان‌بندی ──────────────────────────────────────────────────────────

  Future<void> schedule({
    required AppNotificationType type,
    int? notificationId,
    required String title,
    required String body,
    required DateTime when,
    String? payload,
    bool matchDateTimeComponents = false,
  }) async {
    if (!_initialized || !notificationsEnabled) return;
    if (when.isBefore(DateTime.now())) return;

    final scheduled = tz.TZDateTime.from(when, tz.local);

    await _plugin.zonedSchedule(
      type.id,
      title,
      body,
      scheduled,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: '@mipmap/ic_launcher',
          styleInformation: BigTextStyleInformation(body),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents:
          matchDateTimeComponents ? DateTimeComponents.dayOfWeekAndTime : null,
      payload: payload,
    );
  }

  Future<void> cancel(AppNotificationType type) async {
    await _plugin.cancel(type.id);
  }

  Future<void> _cancelGoldenExpiry() async {
    await _plugin.cancel(AppNotificationType.goldenExpiringThreeDays.id);
    await _plugin.cancel(AppNotificationType.goldenExpiringOneDay.id);
    await _plugin.cancel(AppNotificationType.goldenExpiring.id);
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // سناریوهای محصول (روانشناسی رفتار کاربر)
  // ═══════════════════════════════════════════════════════════════════════════

  /// اعتبار کم — لحن آرام، نه فشار فروش
  Future<void> notifyLowCredits(int credits) async {
    if (!isTypeEnabled(NotificationPrefs.lowCredits)) return;
    if (credits > 2) {
      await cancel(AppNotificationType.lowCredits);
      return;
    }

    final body = credits <= 0
        ? 'وقتی دوباره نیاز داشتی، از فروشگاه بسته مناسب انتخاب کن.'
        : credits == 1
            ? '۱ عیب‌یابی باقی مانده. قبل از نیاز بعدی می‌تونی شارژ کنی.'
            : '$credits عیب‌یابی باقی مانده.';

    await show(
      type: AppNotificationType.lowCredits,
      title: credits <= 0 ? 'اعتبار تمام شده' : 'اعتبار رو به اتمام',
      body: body,
      payload: 'shop',
    );
  }

  /// انقضای اشتراک طلایی — ۳ روز و ۱ روز قبل
  Future<void> scheduleGoldenExpiry(DateTime? expiry) async {
    await _cancelGoldenExpiry();
    if (expiry == null || !isTypeEnabled(NotificationPrefs.golden)) return;

    final now = DateTime.now();
    final threeDays = expiry.subtract(const Duration(days: 3));
    final oneDay = expiry.subtract(const Duration(days: 1));

    if (threeDays.isAfter(now)) {
      await schedule(
        type: AppNotificationType.goldenExpiringThreeDays,
        notificationId: AppNotificationType.goldenExpiringThreeDays.id,
        title: 'اشتراک طلایی',
        body: '۳ روز تا پایان اشتراک طلایی باقی مانده.',
        when: threeDays,
        payload: 'shop',
      );
    }
    if (oneDay.isAfter(now)) {
      await schedule(
        type: AppNotificationType.goldenExpiringOneDay,
        notificationId: AppNotificationType.goldenExpiringOneDay.id,
        title: 'اشتراک طلایی',
        body: 'فردا اشتراک طلایی به پایان می‌رسد. در صورت نیاز تمدید کن.',
        when: oneDay,
        payload: 'shop',
      );
    }
  }

  /// چکاپ دوره‌ای خودرو — پیش‌فرض: هر شنبه ساعت ۱۰ (ملایم، نه اسپم)
  Future<void> scheduleWeeklyCheckup({
    int dayOfWeek = DateTime.saturday, // ۱=دوشنبه … ۷=یکشنبه در DateTime
    int hour = 10,
    int minute = 0,
  }) async {
    await init();
    await cancel(AppNotificationType.checkupReminder);
    if (!isTypeEnabled(NotificationPrefs.checkup)) return;

    // ذخیره تنظیم
    await _prefs?.setInt(NotificationPrefs.checkupDayOfWeek, dayOfWeek);
    await _prefs?.setInt(NotificationPrefs.checkupHour, hour);

    final next = _nextInstanceOfWeekday(dayOfWeek, hour, minute);

    await schedule(
      type: AppNotificationType.checkupReminder,
      title: 'یادآوری چکاپ خودرو',
      body: 'اگر صدای عجیب یا لرزش دیدی، با مکانیک هوشمند سریع بررسی کن.',
      when: next,
      payload: 'home',
      matchDateTimeComponents: true,
    );
  }

  DateTime _nextInstanceOfWeekday(int weekday, int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    while (scheduled.weekday != weekday || !scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// پیشرفت معرفی — حس پیشرفت (Zeigarnik)
  Future<void> notifyReferralProgress({
    required int earnings,
    required int minWithdrawal,
  }) async {
    if (!isTypeEnabled(NotificationPrefs.referral)) return;
    if (minWithdrawal <= 0) return;

    final progress = earnings / minWithdrawal;
    if (progress >= 1.0) {
      await show(
        type: AppNotificationType.referralMilestone,
        title: 'موجودی معرفی آماده برداشت',
        body: 'به سقف برداشت رسیدی. می‌تونی درخواست برداشت بدی.',
        payload: 'shop',
      );
    } else if (progress >= 0.5 && progress < 0.55) {
      // فقط حدود نیمه‌راه یک‌بار
      await show(
        type: AppNotificationType.referralMilestone,
        title: 'نیمه راه برداشت',
        body: 'تقریباً نصف مسیر تا برداشت موجودی معرفی طی شده.',
        payload: 'shop',
      );
    }
  }

  /// خوش‌آمد بعد از ورود اول
  Future<void> notifyWelcome() async {
    final seen = _prefs?.getBool('notif_welcome_shown') ?? false;
    if (seen) return;
    await _prefs?.setBool('notif_welcome_shown', true);

    await show(
      type: AppNotificationType.welcome,
      title: 'خوش آمدی به مکانیک هوشمند',
      body: 'مشکل ماشینت رو بنویس یا صدای موتور رو ضبط کن تا راهنمایی بگیری.',
      payload: 'home',
    );
  }

  /// همگام‌سازی بعد از آپدیت پروفایل (از AuthProvider صدا شود)
  Future<void> syncFromProfile({
    required int credits,
    required bool isGoldenActive,
    DateTime? goldenExpiry,
    int earnings = 0,
    int minWithdrawal = 50000,
  }) async {
    if (!_initialized) {
      _pendingCredits = credits;
      _pendingGoldenActive = isGoldenActive;
      _pendingGoldenExpiry = goldenExpiry;
      _pendingEarnings = earnings;
      _pendingMinWithdrawal = minWithdrawal;
      _hasPendingProfileSync = true;
      return;
    }
    if (!notificationsEnabled) return;

    if (!isGoldenActive) {
      await notifyLowCredits(credits);
    } else {
      await cancel(AppNotificationType.lowCredits);
    }

    await scheduleGoldenExpiry(isGoldenActive ? goldenExpiry : null);
    await notifyReferralProgress(
      earnings: earnings,
      minWithdrawal: minWithdrawal,
    );
  }
}
