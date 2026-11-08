import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ذخیره‌ساز محلی داده‌های اپلیکیشن
///
/// از [ChangeNotifier] ارث‌بری می‌کند تا UI بتواند با
/// `ListenableBuilder` یا `Consumer` به تغییرات واکنش نشان دهد.
class EducationStore extends ChangeNotifier {
  EducationStore(this.prefs);

  final SharedPreferences prefs;

  static Future<EducationStore> open() async =>
      EducationStore(await SharedPreferences.getInstance());

  // ══════════════════════════════════════════════
  //  ثابت‌ها
  // ══════════════════════════════════════════════

  static const _kProfile = 'edu.profile';
  static const _kTasks = 'edu.tasks';
  static const _kExams = 'edu.exams';
  static const _kCards = 'edu.cards';
  static const _kMessages = 'edu.messages';
  static const _kWallet = 'edu.ai.wallet';

  static const _allKeys = [
    _kProfile, _kTasks, _kExams, _kCards, _kMessages, _kWallet,
  ];

  /// تعداد درخواست‌های رایگان هوش مصنوعی
  static const freeAiLimit = 2;

  /// حداکثر پیام ذخیره‌شده در تاریخچه چت
  static const maxMessages = 80;

  // ══════════════════════════════════════════════
  //  Mutex برای عملیات کیف پول
  // ══════════════════════════════════════════════

  /// زنجیره Future برای serializing عملیات کیف پول.
  /// جلوگیری از race condition در read-then-write.
  Future<void> _walletMutex = Future.value();

  Future<T> _withWalletLock<T>(Future<T> Function() action) {
    final previous = _walletMutex;
    final completer = Completer<void>();
    _walletMutex = completer.future;
    return previous
        .then((_) => action())
        .whenComplete(completer.complete);
  }

  // ══════════════════════════════════════════════
  //  پروفایل
  // ══════════════════════════════════════════════

  Map<String, dynamic>? get profile {
    final raw = prefs.getString(_kProfile);
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (e) {
      debugPrint('⚠️ خطا در خواندن پروفایل: $e');
      return null;
    }
  }

  Future<void> saveProfile(Map<String, dynamic> value) async {
    await prefs.setString(_kProfile, jsonEncode(value));
    notifyListeners();
  }

  // ══════════════════════════════════════════════
  //  خواندن/نوشتن لیست (عمومی)
  // ══════════════════════════════════════════════

  List<Map<String, dynamic>> readList(String key) {
    final raw = prefs.getString(key);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (e) {
      debugPrint('⚠️ خطا در خواندن لیست $key: $e');
      return [];
    }
  }

  Future<void> writeList(String key, List<Map<String, dynamic>> value) async {
    await prefs.setString(key, jsonEncode(value));
    notifyListeners();
  }

  // ══════════════════════════════════════════════
  //  کیف پول هوش مصنوعی
  // ══════════════════════════════════════════════

  Map<String, dynamic> get _wallet {
    final raw = prefs.getString(_kWallet);
    if (raw == null) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (e) {
      debugPrint('⚠️ خطا در خواندن کیف پول: $e');
      return {};
    }
  }

  int get credits => (_wallet['credits'] as num?)?.toInt() ?? 0;

  int get successfulAiUses =>
      (_wallet['successful_uses'] as num?)?.toInt() ?? 0;

  int get freeAiUsesRemaining =>
      (freeAiLimit - successfulAiUses).clamp(0, freeAiLimit);

  bool get canUseAi => freeAiUsesRemaining > 0 || credits > 0;

  /// بررسی اینکه آیا توکن خرید قبلاً استفاده شده است
  Future<bool> isPurchaseTokenUsed(String purchaseToken) async {
    final wallet = _wallet;
    final tokens =
        (wallet['purchase_tokens'] as List?)?.cast<String>() ?? <String>[];
    return tokens.contains(purchaseToken);
  }

  /// ثبت یک استفاده موفق از هوش مصنوعی و کسر اعتبار (در صورت نیاز)
  ///
  /// بازگشت `false` به معنای اتمام اعتبار است.
  Future<bool> recordSuccessfulAiUse() => _withWalletLock(() async {
        final wallet = _wallet;
        final uses = (wallet['successful_uses'] as num?)?.toInt() ?? 0;
        final balance = (wallet['credits'] as num?)?.toInt() ?? 0;
        final tokens =
            (wallet['purchase_tokens'] as List?)?.cast<String>() ?? <String>[];

        if (uses >= freeAiLimit && balance <= 0) return false;

        final newBalance = uses >= freeAiLimit ? balance - 1 : balance;

        await prefs.setString(
          _kWallet,
          jsonEncode({
            'credits': newBalance,
            'successful_uses': uses + 1,
            'purchase_tokens': tokens,
          }),
        );

        notifyListeners();
        return true;
      });

  /// افزودن اعتبار از خرید بازار
  ///
  /// بازگشت `false` به معنای تکراری بودن توکن خرید است.
  Future<bool> grantProduct({
    required String productId,
    required String purchaseToken,
    required int creditsToAdd,
  }) {
    if (productId.trim().isEmpty ||
        purchaseToken.trim().isEmpty ||
        creditsToAdd <= 0) {
      throw ArgumentError(
        'شناسه محصول، توکن خرید و تعداد اعتبار معتبر الزامی است.',
      );
    }

    return _withWalletLock(() async {
      final wallet = _wallet;
      final tokens =
          (wallet['purchase_tokens'] as List?)?.cast<String>() ?? <String>[];

      if (tokens.contains(purchaseToken)) return false;

      await prefs.setString(
        _kWallet,
        jsonEncode({
          'credits': ((wallet['credits'] as num?)?.toInt() ?? 0) + creditsToAdd,
          'successful_uses':
              (wallet['successful_uses'] as num?)?.toInt() ?? 0,
          'purchase_tokens': [...tokens, purchaseToken],
        }),
      );

      notifyListeners();
      debugPrint(
        '[Store] ✅ اعتبار اضافه شد: $productId → +$creditsToAdd',
      );
      return true;
    });
  }

  // ══════════════════════════════════════════════
  //  وظایف (Tasks)
  // ══════════════════════════════════════════════

  List<Map<String, dynamic>> get tasks => readList(_kTasks);

  Future<void> addTask(Map<String, dynamic> value) async {
    final all = tasks;
    all.insert(0, value);
    await writeList(_kTasks, all);
  }

  Future<void> toggleTask(String id) async {
    final all = tasks;
    for (final item in all) {
      if (item['id'] == id) {
        item['done'] = !(item['done'] as bool? ?? false);
        break; // فقط اولین match
      }
    }
    await writeList(_kTasks, all);
  }

  Future<void> deleteTask(String id) async =>
      writeList(_kTasks, tasks.where((e) => e['id'] != id).toList());

  // ══════════════════════════════════════════════
  //  آزمون‌ها (Exams)
  // ══════════════════════════════════════════════

  List<Map<String, dynamic>> get exams => readList(_kExams);

  Future<void> addExam(Map<String, dynamic> value) async {
    final all = exams;
    all.insert(0, value);
    await writeList(_kExams, all);
  }

  Future<void> deleteExam(String id) async =>
      writeList(_kExams, exams.where((e) => e['id'] != id).toList());

  // ══════════════════════════════════════════════
  //  فلش‌کارت‌ها (Cards)
  // ══════════════════════════════════════════════

  List<Map<String, dynamic>> get cards => readList(_kCards);

  Future<void> addCard(Map<String, dynamic> value) async {
    final all = cards;
    all.insert(0, value);
    await writeList(_kCards, all);
  }

  Future<void> updateCard(Map<String, dynamic> value) async {
    final all = cards;
    final index = all.indexWhere((e) => e['id'] == value['id']);
    if (index >= 0) all[index] = value;
    await writeList(_kCards, all);
  }

  Future<void> deleteCard(String id) async =>
      writeList(_kCards, cards.where((e) => e['id'] != id).toList());

  // ══════════════════════════════════════════════
  //  پیام‌های چت (Messages)
  // ══════════════════════════════════════════════

  List<Map<String, dynamic>> get messages => readList(_kMessages);

  Future<void> saveMessages(List<Map<String, dynamic>> value) => writeList(
        _kMessages,
        value.length <= maxMessages
            ? value
            : value.sublist(value.length - maxMessages),
      );

  // ══════════════════════════════════════════════
  //  پاک‌سازی کامل
  // ══════════════════════════════════════════════

  Future<void> clear() async {
    for (final key in _allKeys) {
      await prefs.remove(key);
    }
    notifyListeners();
    debugPrint('[Store] 🗑️ تمام داده‌ها پاک شدند.');
  }
}
