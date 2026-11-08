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

  /// زنجیره Future برای serializing 
