import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class EducationStore {
  EducationStore(this.prefs);
  final SharedPreferences prefs;
  static Future<EducationStore> open() async =>
      EducationStore(await SharedPreferences.getInstance());

  Map<String, dynamic>? get profile {
    final raw = prefs.getString('edu.profile');
    if (raw == null) return null;
    try { return Map<String, dynamic>.from(jsonDecode(raw) as Map); } catch (_) { return null; }
  }

  Future<void> saveProfile(Map<String, dynamic> value) =>
      prefs.setString('edu.profile', jsonEncode(value));

  List<Map<String, dynamic>> readList(String key) {
    try {
      return (jsonDecode(prefs.getString(key) ?? '[]') as List)
          .map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) { return []; }
  }

  Future<void> writeList(String key, List<Map<String, dynamic>> value) =>
      prefs.setString(key, jsonEncode(value));


  // Local-only consumable AI wallet. A single JSON preference keeps the
  // balance, successful-use counter and purchase-token ledger in one write.
  Map<String, dynamic> get _wallet {
    try {
      return Map<String, dynamic>.from(
        jsonDecode(prefs.getString('edu.ai.wallet') ?? '{}') as Map,
      );
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  int get credits => (_wallet['credits'] as num?)?.toInt() ?? 0;
  int get successfulAiUses => (_wallet['successful_uses'] as num?)?.toInt() ?? 0;
  int get freeAiUsesRemaining => (2 - successfulAiUses).clamp(0, 2).toInt();
  bool get canUseAi => freeAiUsesRemaining > 0 || credits > 0;

  Future<bool> recordSuccessfulAiUse() async {
    final wallet = _wallet;
    final uses = (wallet['successful_uses'] as num?)?.toInt() ?? 0;
    final balance = (wallet['credits'] as num?)?.toInt() ?? 0;
    if (uses >= 2 && balance <= 0) return false;
    await prefs.setString('edu.ai.wallet', jsonEncode({
      'credits': uses >= 2 ? balance - 1 : balance,
      'successful_uses': uses + 1,
      'purchase_tokens': (wallet['purchase_tokens'] as List?)?.cast<String>() ?? <String>[],
    }));
    return true;
  }

  Future<bool> grantProduct({
    required String productId,
    required String purchaseToken,
    required int creditsToAdd,
  }) async {
    if (productId.trim().isEmpty || purchaseToken.trim().isEmpty || creditsToAdd <= 0) {
      throw ArgumentError('شناسه محصول، توکن خرید و تعداد اعتبار معتبر الزامی است.');
    }
    final wallet = _wallet;
    final tokens = (wallet['purchase_tokens'] as List?)?.cast<String>() ?? <String>[];
    if (tokens.contains(purchaseToken)) return false;
    await prefs.setString('edu.ai.wallet', jsonEncode({
      'credits': ((wallet['credits'] as num?)?.toInt() ?? 0) + creditsToAdd,
      'successful_uses': (wallet['successful_uses'] as num?)?.toInt() ?? 0,
      'purchase_tokens': [...tokens, purchaseToken],
    }));
    return true;
  }

  List<Map<String, dynamic>> get tasks => readList('edu.tasks');
  Future<void> addTask(Map<String, dynamic> value) async {
    final all = tasks..insert(0, value);
    await writeList('edu.tasks', all);
  }
  Future<void> toggleTask(String id) async {
    final all = tasks;
    for (final item in all) {
      if (item['id'] == id) item['done'] = !(item['done'] as bool? ?? false);
    }
    await writeList('edu.tasks', all);
  }
  Future<void> deleteTask(String id) async =>
      writeList('edu.tasks', tasks.where((e) => e['id'] != id).toList());

  List<Map<String, dynamic>> get exams => readList('edu.exams');
  Future<void> addExam(Map<String, dynamic> value) async {
    final all = exams..insert(0, value);
    await writeList('edu.exams', all);
  }
  Future<void> deleteExam(String id) async =>
      writeList('edu.exams', exams.where((e) => e['id'] != id).toList());

  List<Map<String, dynamic>> get cards => readList('edu.cards');
  Future<void> addCard(Map<String, dynamic> value) async {
    final all = cards..insert(0, value);
    await writeList('edu.cards', all);
  }
  Future<void> updateCard(Map<String, dynamic> value) async {
    final all = cards;
    final index = all.indexWhere((e) => e['id'] == value['id']);
    if (index >= 0) all[index] = value;
    await writeList('edu.cards', all);
  }
  Future<void> deleteCard(String id) async =>
      writeList('edu.cards', cards.where((e) => e['id'] != id).toList());

  List<Map<String, dynamic>> get messages => readList('edu.messages');
  Future<void> saveMessages(List<Map<String, dynamic>> value) =>
      writeList('edu.messages', value.length <= 80 ? value : value.sublist(value.length - 80));

  Future<void> clear() async {
    for (final key in ['edu.profile', 'edu.tasks', 'edu.exams', 'edu.cards', 'edu.messages']) {
      await prefs.remove(key);
    }
  }
}
