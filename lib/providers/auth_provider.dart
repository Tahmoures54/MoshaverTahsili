import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/local_first_store.dart';

/// Device-local account state for the Cafe Bazaar build.
///
/// There is no remote login/profile backend in this app variant. The phone is
/// only a local profile label; diagnosis history, trial usage, and credits are
/// managed transactionally by [LocalFirstStore].
class AuthProvider with ChangeNotifier {
  AuthProvider(ApiService _, {LocalFirstStore? localStore})
      : localStore = localStore;

  final LocalFirstStore? localStore;

  int _localCompletedDiagnoses = 0;
  String? _phone;
  bool _isLoading = true;
  bool _isProfileLoaded = false;
  int _credits = 0;
  bool _isGolden = false;
  DateTime? _goldenExpiry;
  int _remainingFree = 2;
  int _monthlyFreeLimit = 2;
  int _usedFree = 0;

  bool get isAuthenticated => _phone?.isNotEmpty ?? false;
  bool get isLoading => _isLoading;
  bool get isProfileLoaded => _isProfileLoaded;
  String? get token => isAuthenticated ? 'local-device' : null;
  String? get userId => null;
  String? get userName => null;
  String? get phone => _phone;

  int get paidCredits => _credits;
  int get credits =>
      _credits > 0 ? _credits : (_remainingFree > 0 ? _remainingFree : 0);
  bool get isGolden => _isGolden;
  DateTime? get goldenExpiry => _goldenExpiry;
  int get remainingFree => _remainingFree;
  int get monthlyFreeLimit => _monthlyFreeLimit;
  int get usedFree => _usedFree;

  // Referral, earnings and withdrawals are not part of the local-only app.
  String? get referralCode => null;
  int get earnings => 0;
  int get referredCount => 0;
  int get referralPercentage => 0;
  int get minWithdrawal => 0;

  bool get isGoldenActive {
    if (!_isGolden) return false;
    if (_goldenExpiry == null) return true;
    return _goldenExpiry!.isAfter(DateTime.now());
  }

  int? get goldenDaysLeft {
    if (!isGoldenActive || _goldenExpiry == null) return null;
    return _goldenExpiry!.difference(DateTime.now()).inDays;
  }

  String get displayName => _phone?.isNotEmpty == true ? _phone! : 'کاربر';

  bool get shouldShowPlans =>
      _localCompletedDiagnoses >= 2 && _credits <= 0 && !isGoldenActive;

  bool get canDiagnose {
    if (!isAuthenticated) return false;
    if (isGoldenActive || _credits > 0) return true;
    return _localCompletedDiagnoses < 2;
  }

  Future<void> checkAuthStatus() async {
    _isLoading = true;
    notifyListeners();
    try {
      _phone = await localStore?.phone;
      await refreshLocalState();
      _isProfileLoaded = isAuthenticated;
    } catch (e) {
      debugPrint('[AuthProvider] خواندن پروفایل محلی ناموفق بود: $e');
      _phone = null;
      _isProfileLoaded = false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshLocalState() async {
    final store = localStore;
    if (store == null) return;

    final status = await store.trialStatus;
    final profile = await store.profile;
    _localCompletedDiagnoses = status.completedDiagnoses;
    _usedFree = status.completedDiagnoses;
    _remainingFree = math.max(0, 2 - status.completedDiagnoses);
    _credits = await store.credits;
    _isGolden = await store.isGoldenActive;
    final expiry = profile['golden_until_ms'] as int?;
    _goldenExpiry = expiry == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(expiry);
    notifyListeners();
  }

  Future<void> saveLocalPhone(String value) async {
    final store = localStore;
    if (store == null) {
      throw StateError('ذخیره‌سازی محلی پیکربندی نشده است.');
    }
    await store.savePhone(value);
    _phone = value.trim();
    _isProfileLoaded = true;
    await refreshLocalState();
  }

  // Compatibility wrappers: this build intentionally has no OTP/server login.
  Future<void> sendOtp(String phone) => saveLocalPhone(phone);

  Future<void> login(String phone, String code, {String? referralCode}) =>
      saveLocalPhone(phone);

  Future<void> fetchProfile({bool force = false}) => refreshLocalState();

  Future<void> logout() async {
    final store = localStore;
    if (store != null) await store.clearPhone();
    _phone = null;
    _isProfileLoaded = false;
    notifyListeners();
  }

  // These legacy UI hooks no longer grant or consume entitlement by themselves.
  // The local SQLite transaction in ApiService.saveDiagnosis is authoritative.
  void updateCredits(int newCredits) {
    unawaited(refreshLocalState());
  }

  void addCredits(int amount) {
    unawaited(refreshLocalState());
  }

  @Deprecated('Diagnosis credits are consumed atomically by LocalFirstStore.')
  void consumeCredit() {
    unawaited(refreshLocalState());
  }

  void applyDiagnoseQuota({
    int? remainingCredits,
    int? remainingFreeQuestions,
  }) {
    unawaited(refreshLocalState());
  }

  void activateGolden({DateTime? expiry}) {
    unawaited(refreshLocalState());
  }

  Future<bool> validateToken() async => isAuthenticated;
}
