import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Thrown instead of silently resetting a damaged local wallet or workspace.
class LocalDataException implements Exception {
  const LocalDataException(this.message);
  final String message;
  @override
  String toString() => message;
}

class AiReservation {
  const AiReservation({this.cachedAnswer, required this.usesFreeUse});
  final String? cachedAnswer;
  final bool usesFreeUse;
  bool get isCompleted => cachedAnswer != null;
}

/// Lightweight, device-local storage. All read/modify/write operations are
/// serialized. Balance, request state and its ledger are persisted in ONE key.
/// This is not a tamper-proof or server-verified financial ledger.
class EducationStore extends ChangeNotifier {
  EducationStore(this.prefs) {
    try {
      _wallet = _decodeWallet(prefs.getString(walletKey));
    } on Object {
      _walletError = 'اطلاعات کیف پول خوانده نشد. برای جلوگیری از دست رفتن اعتبار، داده قبلی بازنویسی نمی‌شود.';
    }
  }

  final SharedPreferences prefs;
  static const walletKey = 'edu.ai.wallet';
  static const freeUses = 2;
  static const maxQuestionLength = 4000;
  static const maxAnswerLength = 24000;
  static const maxHistoryEntries = 250;
  static const maxStoredRequests = 100;
  static const workspaceKeys = [
    'edu.profile', 'edu.tasks', 'edu.exams', 'edu.cards',
    'edu.messages', 'edu.reports', 'edu.career.draft',
  ];

  Future<void> _tail = Future<void>.value();
  final Set<String> _activeRequests = {};
  final Map<String, String> _dataErrors = {};
  Map<String, dynamic> _wallet = _emptyWallet();
  String? _walletError;
  String? get walletError => _walletError;
  String? dataError(String key) => _dataErrors[key];

  static Future<EducationStore> open() async {
    final store = EducationStore(await SharedPreferences.getInstance());
    await store.refundInterruptedRequests();
    return store;
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    // A failed write must not poison subsequent operations.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  static Map<String, dynamic> _emptyWallet() => {
    'version': 2,
    'credits': 0,
    'successful_uses': 0,
    'purchase_tokens': <String, dynamic>{},
    'requests': <String, dynamic>{},
    'transactions': <Map<String, dynamic>>[],
  };

  static int _nonNegativeInt(Object? value) {
    if (value is! int || value < 0 || value > 1000000000) {
      throw const FormatException('Invalid counter');
    }
    return value;
  }

  static String _string(Object? value, int limit) {
    if (value is! String || value.length > limit) throw const FormatException('Invalid string');
    return value;
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is! Map) throw const FormatException('Invalid object');
    return value.map((key, Object? item) => MapEntry(_string(key, 512), item));
  }

  /// Migrates v1 wallets without discarding balances or previously used tokens.
  static Map<String, dynamic> _decodeWallet(String? raw) {
    if (raw == null) return _emptyWallet();
    if (raw.length > 4000000) throw const FormatException('Wallet too large');
    final source = _map(jsonDecode(raw));
    final result = _emptyWallet();
    result['credits'] = _nonNegativeInt(source['credits'] ?? 0);
    result['successful_uses'] = _nonNegativeInt(source['successful_uses'] ?? 0);
    final tokens = <String, dynamic>{};
    final oldTokens = source['purchase_tokens'];
    if (oldTokens is List) {
      for (final token in oldTokens) {
        final id = _string(token, 512);
        if (id.trim().isEmpty) throw const FormatException('Empty token');
        tokens[id] = {'productId': 'legacy', 'credits': 0};
      }
    } else if (oldTokens != null) {
      oldTokens.forEach((Object? key, Object? value) {
        final id = _string(key, 512);
        final item = _map(value);
        if (id.trim().isEmpty) throw const FormatException('Empty token');
        tokens[id] = {
          'productId': _string(item['productId'], 100),
          'credits': _nonNegativeInt(item['credits']),
          if (item['createdAt'] != null) 'createdAt': _string(item['createdAt'], 40),
        };
      });
    }
    result['purchase_tokens'] = tokens;
    final requests = <String, dynamic>{};
    if (source['requests'] != null) {
      _map(source['requests']).forEach((id, Object? value) {
        final item = _map(value);
        final status = _string(item['status'], 20);
        final charge = _string(item['charge'], 20);
        if (!{'pending', 'completed', 'refunded'}.contains(status) ||
            !{'free', 'credit'}.contains(charge)) {
          throw const FormatException('Invalid request state');
        }
        requests[id] = {
          'question': _string(item['question'], maxQuestionLength),
          'status': status,
          'charge': charge,
          'createdAt': _string(item['createdAt'], 40),
          if (item['attempt'] != null) 'attempt': _nonNegativeInt(item['attempt']),
          if (item['transactionId'] != null) 'transactionId': _string(item['transactionId'], 512),
          if (item['answer'] != null) 'answer': _string(item['answer'], maxAnswerLength),
        };
        if (status == 'completed' && requests[id]['answer'] == null) {
          throw const FormatException('Missing saved answer');
        }
      });
    }
    result['requests'] = requests;
    final transactions = <Map<String, dynamic>>[];
    if (source['transactions'] != null) {
      if (source['transactions'] is! List) throw const FormatException('Invalid ledger');
      for (final Object? value in source['transactions'] as List) {
        final item = _map(value);
        final kind = _string(item['kind'], 20);
        if (!{'purchase', 'ai', 'refund'}.contains(kind)) throw const FormatException('Invalid transaction');
        transactions.add({
          'id': _string(item['id'], 512),
          'kind': kind,
          'amount': _nonNegativeInt(item['amount']),
          'title': _string(item['title'], 160),
          'createdAt': _string(item['createdAt'], 40),
          'status': _string(item['status'], 20),
        });
      }
    }
    result['transactions'] = transactions;
    return result;
  }

  Map<String, dynamic> _checkedWallet() {
    if (_walletError != null) throw LocalDataException(_walletError!);
    return _wallet;
  }

  int get credits => _walletError != null ? 0 : _wallet['credits'] as int;
  int get successfulAiUses => _walletError != null ? 0 : _wallet['successful_uses'] as int;
  int get freeAiUsesRemaining {
    if (_walletError != null) return 0;
    final pendingFree = (_wallet['requests'] as Map).values
        .where((Object? item) => item is Map && item['status'] == 'pending' && item['charge'] == 'free')
        .length;
    return (freeUses - successfulAiUses - pendingFree).clamp(0, freeUses).toInt();
  }
  bool get hasActiveAiRequests => _activeRequests.isNotEmpty;
  bool get canUseAi => _walletError == null && (freeAiUsesRemaining > 0 || credits > 0);
  String? savedAiAnswer(String id) {
    if (_walletError != null) return null;
    final request = (_wallet['requests'] as Map)[id] as Map?;
    final answer = request?['answer'];
    return request?['status'] == 'completed' && answer is String ? answer : null;
  }

  List<Map<String, dynamic>> get creditHistory {
    if (_walletError != null) return const [];
    return (_wallet['transactions'] as List).reversed
        .map((Object? item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<void> _saveWallet(Map<String, dynamic> wallet) async {
    final raw = jsonEncode(wallet);
    // Validate the exact data to be written before touching existing storage.
    _decodeWallet(raw);
    if (!await prefs.setString(walletKey, raw)) {
      throw const LocalDataException('ذخیره کیف پول انجام نشد. فضای خالی گوشی را بررسی کن و دوباره تلاش کن.');
    }
    _wallet = wallet;
    notifyListeners();
  }

  Map<String, dynamic> _copyWallet() => _decodeWallet(jsonEncode(_checkedWallet()));
  String _now() => DateTime.now().toUtc().toIso8601String();

  void _transaction(Map<String, dynamic> wallet, String id, String kind,
      int amount, String title, String status) {
    if (amount == 0 && kind != 'ai') return;
    final history = wallet['transactions'] as List;
    history.add({'id': id, 'kind': kind, 'amount': amount, 'title': title,
      'createdAt': _now(), 'status': status});
    if (history.length > maxHistoryEntries) history.removeAt(0);
  }

  void _markTransaction(Map<String, dynamic> wallet, String id, String status) {
    final history = wallet['transactions'] as List;
    for (var index = history.length - 1; index >= 0; index--) {
      final transaction = history[index] as Map;
      if (transaction['id'] == id && transaction['kind'] == 'ai') {
        transaction['status'] = status;
        return;
      }
    }
  }

  void _trimRequests(Map<String, dynamic> wallet) {
    final requests = wallet['requests'] as Map<String, dynamic>;
    final removable = requests.entries.where((entry) => entry.value['status'] != 'pending').toList();
    while (requests.length > maxStoredRequests && removable.isNotEmpty) {
      requests.remove(removable.removeAt(0).key);
    }
  }

  /// A reservation prevents concurrent requests overdrawing the local balance.
  /// Failed requests are refunded; completed request IDs return the saved answer
  /// without another network call or charge, including after an app restart.
  Future<AiReservation> prepareAiRequest({required String id, required String question}) =>
      _serialized(() async {
        _validateId(id);
        if (question.trim().isEmpty || question.length > maxQuestionLength) {
          throw const LocalDataException('متن درخواست باید بین ۱ تا ۴۰۰۰ نویسه باشد.');
        }
        if (_activeRequests.contains(id)) {
          throw const LocalDataException('این درخواست در حال انجام است. صبر کن تا پاسخ برسد.');
        }
        final wallet = _copyWallet();
        final requests = wallet['requests'] as Map<String, dynamic>;
        final previous = requests[id] as Map<String, dynamic>?;
        if (previous != null && previous['question'] != question) {
          throw const LocalDataException('شناسه درخواست برای متن دیگری ثبت شده است.');
        }
        if (previous?['status'] == 'completed') {
          return AiReservation(cachedAnswer: previous!['answer'] as String,
              usesFreeUse: previous['charge'] == 'free');
        }
        var charge = previous?['charge'] ?? (freeAiUsesRemaining > 0 ? 'free' : 'credit');
        if (charge == 'free' && previous?['status'] == 'refunded' && freeAiUsesRemaining == 0) {
          charge = 'credit';
        }
        if (charge == 'credit' && credits < 1) {
          throw const LocalDataException('اعتبار کافی نداری. برای ادامه، بسته اعتبار تهیه کن.');
        }
        if (charge == 'credit') wallet['credits'] = credits - 1;
        final attempt = previous == null ? 1 : ((previous['attempt'] as int?) ?? 1) + 1;
        final transactionId = '$id-attempt-$attempt';
        requests[id] = {'question': question, 'status': 'pending', 'charge': charge,
          'createdAt': previous?['createdAt'] ?? _now(),
          'attempt': attempt, 'transactionId': transactionId};
        _transaction(wallet, transactionId, 'ai', charge == 'credit' ? 1 : 0, 'درخواست مشاور هوشمند', 'pending');
        _trimRequests(wallet);
        await _saveWallet(wallet);
        _activeRequests.add(id);
        return AiReservation(usesFreeUse: charge == 'free');
      });

  Future<void> completeAiRequest(String id, String answer) => _serialized(() async {
    final wallet = _copyWallet();
    final request = (wallet['requests'] as Map)[id] as Map?;
    if (request?['status'] == 'completed') return;
    if (request == null || request['status'] != 'pending' ||
        answer.trim().isEmpty || answer.length > maxAnswerLength) {
      throw const LocalDataException('وضعیت درخواست یا پاسخ دریافتی معتبر نیست.');
    }
    request['status'] = 'completed';
    request['answer'] = answer;
    if (request['charge'] == 'free') {
      wallet['successful_uses'] = successfulAiUses + 1;
    }
    _markTransaction(wallet, (request['transactionId'] as String?) ?? id, 'completed');
    _activeRequests.remove(id);
    await _saveWallet(wallet);
  });

  Future<void> refundAiRequest(String id) => _serialized(() async {
    final wallet = _copyWallet();
    final request = (wallet['requests'] as Map)[id] as Map?;
    if (request == null || request['status'] != 'pending') return;
    request['status'] = 'refunded';
    if (request['charge'] == 'credit') wallet['credits'] = credits + 1;
    final transactionId = (request['transactionId'] as String?) ?? id;
    _markTransaction(wallet, transactionId, 'refunded');
    _transaction(wallet, '$transactionId-refund', 'refund', request['charge'] == 'credit' ? 1 : 0,
        'بازگشت اعتبار درخواست ناموفق', 'completed');
    _activeRequests.remove(id);
    await _saveWallet(wallet);
  });

  /// Called once at startup, before any request can become active.
  Future<void> refundInterruptedRequests() => _serialized(() async {
    if (_walletError != null) return;
    final pending = (_wallet['requests'] as Map).entries
        .where((entry) => entry.value['status'] == 'pending').map((entry) => entry.key.toString()).toList();
    if (pending.isEmpty) return;
    final wallet = _copyWallet();
    for (final id in pending) {
      final request = (wallet['requests'] as Map)[id] as Map;
      request['status'] = 'refunded';
      // Accumulate each refund against the working copy. Reading the store's
      // original balance here loses all but the final refund when several
      // requests were interrupted before the app was closed.
      if (request['charge'] == 'credit') {
        wallet['credits'] = (wallet['credits'] as int) + 1;
      }
      final transactionId = (request['transactionId'] as String?) ?? id;
      _markTransaction(wallet, transactionId, 'refunded');
      _transaction(wallet, '$transactionId-refund', 'refund', request['charge'] == 'credit' ? 1 : 0,
          'بازگشت رزرو پس از بسته شدن برنامه', 'completed');
    }
    await _saveWallet(wallet);
  });

  /// Backwards-compatible entry point; new callers should use the reservation API.
  Future<bool> recordSuccessfulAiUse({String? requestId}) => _serialized(() async {
    final id = requestId ?? 'legacy-${DateTime.now().microsecondsSinceEpoch}';
    final wallet = _copyWallet();
    final requests = wallet['requests'] as Map;
    if (requests.containsKey(id)) return false;
    final free = freeAiUsesRemaining > 0;
    if (!free && credits < 1) return false;
    if (free) {
      wallet['successful_uses'] = successfulAiUses + 1;
    } else {
      wallet['credits'] = credits - 1;
    }
    requests[id] = {'question': 'درخواست ثبت‌شده', 'status': 'completed',
      'charge': free ? 'free' : 'credit', 'createdAt': _now(), 'answer': 'پاسخ دریافت شده'};
    _transaction(wallet, id, 'ai', free ? 0 : 1, 'پاسخ موفق مشاور هوشمند', 'completed');
    _trimRequests(wallet);
    await _saveWallet(wallet);
    return true;
  });

  /// Returns false for an already-credited token. Never credits an arbitrary
  /// product/amount pair: the product ID must exist in the local catalog.
  Future<bool> grantProduct({required String productId, required String purchaseToken, required int creditsToAdd}) =>
      _serialized(() async {
        _validateId(purchaseToken, limit: 512);
        final product = CreditCatalog.byId(productId);
        if (product == null || product.credits != creditsToAdd) {
          throw const LocalDataException('بسته اعتبار یا تعداد اعتبار آن معتبر نیست.');
        }
        final wallet = _copyWallet();
        final tokens = wallet['purchase_tokens'] as Map;
        if (tokens.containsKey(purchaseToken)) return false;
        tokens[purchaseToken] = {'productId': productId, 'credits': creditsToAdd, 'createdAt': _now()};
        wallet['credits'] = credits + creditsToAdd;
        _transaction(wallet, 'purchase-${tokens.length}', 'purchase', creditsToAdd,
            product.title, 'completed');
        await _saveWallet(wallet);
        return true;
      });

  static void _validateId(String value, {int limit = 160}) {
    if (value.trim().isEmpty || value.length > limit) {
      throw const LocalDataException('شناسه محلی معتبر نیست.');
    }
  }

  Map<String, dynamic>? get profile {
    const key = 'edu.profile';
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      return _map(jsonDecode(raw));
    } on Object {
      _dataErrors[key] = 'پروفایل قبلی قابل خواندن نیست و بازنویسی نشده است.';
      return null;
    }
  }

  Future<void> saveProfile(Map<String, dynamic> value) => _writeMap('edu.profile', value);
  Future<void> _writeMap(String key, Map<String, dynamic> value) => _serialized(() async {
    if (_dataErrors.containsKey(key)) throw LocalDataException(_dataErrors[key]!);
    if (!await prefs.setString(key, jsonEncode(value))) {
      throw const LocalDataException('ذخیره اطلاعات انجام نشد. فضای خالی گوشی را بررسی کن.');
    }
    notifyListeners();
  });

  List<Map<String, dynamic>> readList(String key) {
    final raw = prefs.getString(key);
    if (raw == null) return [];
    try {
      final value = jsonDecode(raw);
      if (value is! List) throw const FormatException('Expected list');
      return value.map(_map).toList();
    } on Object {
      _dataErrors[key] = 'اطلاعات قبلی قابل خواندن نیست و بازنویسی نشده است.';
      return [];
    }
  }

  Future<void> writeList(String key, List<Map<String, dynamic>> value) => _serialized(() async {
    if (_dataErrors.containsKey(key)) throw LocalDataException(_dataErrors[key]!);
    if (!await prefs.setString(key, jsonEncode(value))) {
      throw const LocalDataException('ذخیره اطلاعات انجام نشد. فضای خالی گوشی را بررسی کن.');
    }
    notifyListeners();
  });

  Future<void> _mutateList(String key,
      List<Map<String, dynamic>> Function(List<Map<String, dynamic>>) update) =>
      _serialized(() async {
        if (_dataErrors.containsKey(key)) throw LocalDataException(_dataErrors[key]!);
        final current = readList(key);
        final next = update(current);
        if (!await prefs.setString(key, jsonEncode(next))) {
          throw const LocalDataException('ذخیره اطلاعات انجام نشد. فضای خالی گوشی را بررسی کن.');
        }
        notifyListeners();
      });

  List<Map<String, dynamic>> get tasks => readList('edu.tasks');
  Future<void> addTask(Map<String, dynamic> value) =>
      _mutateList('edu.tasks', (all) => [value, ...all]);
  Future<void> toggleTask(String id) => _mutateList('edu.tasks', (all) {
    for (final item in all) {
      if (item['id'] == id) item['done'] = !(item['done'] as bool? ?? false);
    }
    return all;
  });
  Future<void> deleteTask(String id) =>
      _mutateList('edu.tasks', (all) => all.where((e) => e['id'] != id).toList());

  List<Map<String, dynamic>> get exams => readList('edu.exams');
  Future<void> addExam(Map<String, dynamic> value) =>
      _mutateList('edu.exams', (all) => [value, ...all]);
  Future<void> deleteExam(String id) =>
      _mutateList('edu.exams', (all) => all.where((e) => e['id'] != id).toList());

  List<Map<String, dynamic>> get cards => readList('edu.cards');
  Future<void> addCard(Map<String, dynamic> value) =>
      _mutateList('edu.cards', (all) => [value, ...all]);
  Future<void> updateCard(Map<String, dynamic> value) => _mutateList('edu.cards', (all) {
    final index = all.indexWhere((e) => e['id'] == value['id']);
    if (index >= 0) all[index] = value;
    return all;
  });
  Future<void> deleteCard(String id) =>
      _mutateList('edu.cards', (all) => all.where((e) => e['id'] != id).toList());

  List<Map<String, dynamic>> get messages => readList('edu.messages');
  Future<void> saveMessages(List<Map<String, dynamic>> value) => writeList('edu.messages',
      value.length <= 80 ? value : value.sublist(value.length - 80));

  List<Map<String, dynamic>> get reports => readList('edu.reports');
  Future<void> addReport(Map<String, dynamic> value) =>
      _mutateList('edu.reports', (all) => [value, ...all].take(50).toList());
  Future<void> deleteReport(String id) =>
      _mutateList('edu.reports', (all) => all.where((e) => e['id'] != id).toList());
  Map<String, dynamic>? get careerDraft {
    final raw = prefs.getString('edu.career.draft');
    if (raw == null) return null;
    try { return _map(jsonDecode(raw)); } on Object { return null; }
  }
  Future<void> saveCareerDraft(Map<String, dynamic> value) => _writeMap('edu.career.draft', value);

  /// Does NOT delete purchased credits, purchase tokens or financial history.
  Future<void> clear() => _serialized(() async {
    for (final key in workspaceKeys) {
      if (!await prefs.remove(key)) {
        throw const LocalDataException('حذف کامل اطلاعات انجام نشد. دوباره تلاش کن.');
      }
      _dataErrors.remove(key);
    }
    notifyListeners();
  });
}

class CreditProduct {
  const CreditProduct(this.id, this.title, this.credits, this.description);
  final String id, title, description;
  final int credits;
}

/// Existing SKUs retained from this repository, NOT guessed replacement IDs.
/// Checkout additionally requires explicit developer confirmation against the
/// reference project/Bazaar panel; a public key alone does not verify a catalog.
class CreditCatalog {
  static const products = [
    CreditProduct('credit_10', 'بسته برنزی', 10, 'برای شروع و استفاده محدود'),
    CreditProduct('credit_35', 'بسته نقره‌ای', 25, 'برای استفاده بیشتر'),
    CreditProduct('credit_90', 'بسته طلایی', 60, 'برای استفاده پرتکرار'),
  ];
  static CreditProduct? byId(String id) {
    for (final product in products) {
      if (product.id == id) return product;
    }
    return null;
  }
}
