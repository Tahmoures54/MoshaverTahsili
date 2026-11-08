import 'package:flutter/material.dart';

import '../services/notification_service.dart';

/// صفحه تنظیمات اعلان‌ها
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen>
    with WidgetsBindingObserver {
  final _svc = NotificationService.instance;

  bool _enabled = true;
  bool _lowCredits = true;
  bool _golden = true;
  bool _checkup = true;
  bool _referral = true;
  bool _permissionGranted = false;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermission();
    }
  }

  Future<void> _load() async {
    try {
      try {
        await _svc.init();
      } catch (e) {
        debugPrint(
            '[NotificationSettings] notification service unavailable: $e');
      }

      final granted = await _svc.isPermissionGranted;
      if (!mounted) return;

      setState(() {
        _enabled = _svc.notificationsEnabled;
        _lowCredits = _svc.isTypeEnabled(NotificationPrefs.lowCredits);
        _golden = _svc.isTypeEnabled(NotificationPrefs.golden);
        _checkup = _svc.isTypeEnabled(NotificationPrefs.checkup);
        _referral = _svc.isTypeEnabled(NotificationPrefs.referral);
        _permissionGranted = granted;
      });
    } catch (e, st) {
      debugPrint('[NotificationSettings] load failed: $e\n$st');
      _showSnack('خطا در بارگذاری تنظیمات اعلان');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _refreshPermission() async {
    try {
      final granted = await _svc.isPermissionGranted;
      if (!mounted) return;
      if (granted != _permissionGranted) {
        setState(() => _permissionGranted = granted);
      }
    } catch (e) {
      debugPrint('[NotificationSettings] refresh permission failed: $e');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _requestPermission() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await _svc.requestPermission();
      if (!mounted) return;
      setState(() => _permissionGranted = ok);
      if (ok) {
        _showSnack('مجوز اعلان فعال شد');
      } else {
        _showSnack('مجوز اعلان داده نشد');
      }
    } catch (e) {
      debugPrint('[NotificationSettings] requestPermission failed: $e');
      _showSnack('درخواست مجوز ناموفق بود');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testNotification() async {
    try {
      await _svc.show(
        type: AppNotificationType.general,
        title: 'تست اعلان',
        body: 'اگر این پیام را می‌بینی، نوتیفیکیشن درست کار می‌کند.',
        payload: 'home',
      );
    } catch (e) {
      debugPrint('[NotificationSettings] test notification failed: $e');
      _showSnack('ارسال اعلان تست ناموفق بود');
    }
  }

  Future<void> _setEnabled(bool value) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _svc.setNotificationsEnabled(value);
      if (!mounted) return;
      setState(() => _enabled = value);

      if (value) {
        if (_checkup) {
          await _svc.scheduleWeeklyCheckup();
        }
      } else {
        await _svc.cancel(AppNotificationType.checkupReminder);
      }
    } catch (e) {
      debugPrint('[NotificationSettings] setEnabled failed: $e');
      _showSnack('تغییر وضعیت اعلان‌ها ناموفق بود');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setType(
    String prefKey,
    bool value, {
    required void Function(bool) apply,
    bool toggleCheckupSchedule = false,
  }) async {
    try {
      await _svc.setTypeEnabled(prefKey, value);
      if (!mounted) return;
      setState(() => apply(value));

      if (toggleCheckupSchedule) {
        if (value) {
          if (_enabled) {
            await _svc.scheduleWeeklyCheckup();
          }
        } else {
          await _svc.cancel(AppNotificationType.checkupReminder);
        }
      }
    } catch (e) {
      debugPrint('[NotificationSettings] setType($prefKey) failed: $e');
      _showSnack('ذخیره تنظیمات ناموفق بود');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('تنظیمات اعلان')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('تنظیمات اعلان'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (!_permissionGranted)
            Card(
              margin: const EdgeInsets.all(16),
              color: theme.colorScheme.secondary.withOpacity(0.12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'برای دریافت یادآوری‌ها، مجوز اعلان لازم است.',
                      style: TextStyle(height: 1.4),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _busy ? null : _requestPermission,
                      child: const Text('فعال‌سازی مجوز'),
                    ),
                  ],
                ),
              ),
            ),

          SwitchListTile(
            title: const Text('فعال بودن اعلان‌ها'),
            subtitle: const Text('خاموش کردن همه یادآوری‌ها'),
            value: _enabled,
            onChanged: _busy ? null : _setEnabled,
          ),
          const Divider(),

          SwitchListTile(
            title: const Text('اعتبار کم'),
            subtitle:
                const Text('یادآوری ملایم وقتی اعتبار رو به اتمام است'),
            value: _lowCredits && _enabled,
            onChanged: !_enabled
                ? null
                : (v) => _setType(
                      NotificationPrefs.lowCredits,
                      v,
                      apply: (val) => _lowCredits = val,
                    ),
          ),
          SwitchListTile(
            title: const Text('انقضای اشتراک طلایی'),
            subtitle: const Text('چند روز قبل از پایان اشتراک'),
            value: _golden && _enabled,
            onChanged: !_enabled
                ? null
                : (v) => _setType(
                      NotificationPrefs.golden,
                      v,
                      apply: (val) => _golden = val,
                    ),
          ),
          SwitchListTile(
            title: const Text('چکاپ دوره‌ای خودرو'),
            subtitle:
                const Text('یادآوری هفتگی برای بررسی وضعیت ماشین'),
            value: _checkup && _enabled,
            onChanged: !_enabled
                ? null
                : (v) => _setType(
                      NotificationPrefs.checkup,
                      v,
                      apply: (val) => _checkup = val,
                      toggleCheckupSchedule: true,
                    ),
          ),
          SwitchListTile(
            title: const Text('پیشرفت معرفی'),
            subtitle:
                const Text('وقتی به مراحل برداشت نزدیک می‌شوی'),
            value: _referral && _enabled,
            onChanged: !_enabled
                ? null
                : (v) => _setType(
                      NotificationPrefs.referral,
                      v,
                      apply: (val) => _referral = val,
                    ),
          ),

          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('ارسال اعلان تست'),
            subtitle: const Text('برای اطمینان از صحت تنظیمات'),
            enabled: _enabled && _permissionGranted && !_busy,
            onTap: (_enabled && _permissionGranted && !_busy)
                ? _testNotification
                : null,
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'اعلان‌ها با لحن آرام و بدون فشار طراحی شده‌اند تا فقط وقتی مفیدند یادآوری کنند.',
              style: TextStyle(
                fontSize: 12,
                color: theme.hintColor,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
