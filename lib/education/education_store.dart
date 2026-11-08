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


  // Local-only consumable AI credit wallet. The first two successful AI requests
  // are free; subsequent successful requests consume one purchased credit.
  int get credits => prefs.getInt('edu.ai.credits') ?? 0;
  int get successfulAiUses => prefs.getInt('edu.ai.successful_uses') ?? 0;
  int get freeAiUsesRemaining => (2 - successfulAiUses).clamp(0, 2);
  bool get canUseAi => freeAiUsesRemaining > 0 || credits > 0;

  Future<bool> recordSuccessfulAiUse() async {
    final uses = successfulAiUses;
    if (uses < 2) {
      await prefs.setInt('edu.ai.successful_uses', uses + 1);
      return true;
    }
    final balance = credits;
    if (balance <= 0) return false;
    await prefs.setInt('edu.ai.credits', balance - 1);
    await prefs.setInt('edu.ai.successful_uses', uses + 1);
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
    final tokens = prefs.getStringList('edu.ai.purchase_tokens') ?? <String>[];
    if (tokens.contains(purchaseToken)) return false;
    // Persist the unique purchase token before increasing the wallet. This
    // favors duplicate prevention if the process is interrupted mid-write.
    await prefs.setStringList('edu.ai.purchase_tokens', [...tokens, purchaseToken]);
    await prefs.setInt('edu.ai.credits', credits + creditsToAdd);
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
