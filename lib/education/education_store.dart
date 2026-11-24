import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'learning_engine.dart';

abstract interface class SecureLocalCipher {
  Future<String> encrypt(String plaintext, {required String key});

  Future<String> decrypt(String ciphertext, {required String key});
}

class AndroidKeystoreCipher implements SecureLocalCipher {
  const AndroidKeystoreCipher();

  static const _channel = MethodChannel('ir.moshaver.tahsili/secure_storage');

  @override
  Future<String> encrypt(String plaintext, {required String key}) async {
    final value = await _channel.invokeMethod<String>('encrypt', {
      'plaintext': plaintext,
      'key': key,
    });

    if (value == null || !value.startsWith(EducationStore.encryptedPrefix)) {
      throw const LocalDataException('رمزنگاری اطلاعات محلی پاسخ معتبر نداد.');
    }

    return value;
  }

  @override
  Future<String> decrypt(String ciphertext, {required String key}) async {
    if (!ciphertext.startsWith(EducationStore.encryptedPrefix)) {
      throw const LocalDataException(
        'نسخه رمزنگاری اطلاعات محلی پشتیبانی نمی‌شود.',
      );
    }

    final value = await _channel.invokeMethod<String>('decrypt', {
      'ciphertext': ciphertext,
      'key': key,
    });

    if (value == null) {
      throw const LocalDataException('رمزگشایی اطلاعات محلی ناموفق بود.');
    }

    return value;
  }
}

/// Raised instead of silently resetting damaged local data.
class LocalDataException implements Exception {
  const LocalDataException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Information returned by a durable AI reservation.
///
/// Pass [attempt] to completion/refund methods to prevent a late callback
/// from an older attempt from changing a newer attempt using the same ID.
class AiReservation {
  const AiReservation({
    this.cachedAnswer,
    required this.usesFreeUse,
    this.attempt = 1,
  });

  final String? cachedAnswer;
  final bool usesFreeUse;
  final int attempt;

  bool get isCompleted => cachedAnswer != null;
}

/// Device-local encrypted storage.
///
/// Read/modify/write operations are serialized within THIS instance only.
/// Use one shared EducationStore for a given preference namespace.
///
/// Balance, request states and purchase tokens are stored in one wallet key.
/// This reduces multi-key inconsistencies but is not a server-verified,
/// rollback-proof or transactionally durable financial ledger.
///
/// Workspace import/clear supports best-effort rollback for caught failures,
/// not atomic recovery after process termination.
class EducationStore extends ChangeNotifier {
  EducationStore(
    this.prefs, {
    required this.cipher,
    @visibleForTesting Future<bool> Function(String key)? removePreference,
  }) : _wallet = _emptyWallet(),
       _removePreference = removePreference ?? prefs.remove;

  final SharedPreferences prefs;
  final SecureLocalCipher cipher;
  final Future<bool> Function(String key) _removePreference;

  static SecureLocalCipher? secureCipherOverride;

  static const encryptedPrefix = 'enc:v2:';
  static const walletKey = 'edu.ai.wallet';

  static const currentWalletVersion = 3;

  /// Retained only for wallets created before v3.
  static const freeUses = 2;

  static const questionFeatherCost = 1;
  static const maxQuestionLength = 4000;
  static const maxAnswerLength = 24000;
  static const maxHistoryEntries = 250;
  static const maxStoredRequests = 100;
  static const maxWalletBytes = 4 * 1024 * 1024;
  static const maxCounterValue = 1000000000;

  static const workspaceKeys = [
    'edu.profile',
    'edu.tasks',
    'edu.exams',
    'edu.cards',
    'edu.messages',
    'edu.teaching.sessions',
    'edu.reports',
    'edu.career.draft',
    'edu.deadlines',
  ];

  final Map<String, String> _secureData = {};
  final Map<String, String> _dataErrors = {};

  /// Request IDs currently owned by this running instance.
  final Set<String> _activeRequests = {};

  Future<void> _tail = Future<void>.value();

  Map<String, dynamic> _wallet;
  String? _walletError;

  bool _disposed = false;
  bool _initialized = false;

  String? get walletError => _walletError;

  bool get isInitialized => _initialized;

  String? dataError(String key) => _dataErrors[key];

  /// Diagnostic/test access only.
  /// Never render or log this plaintext.
  String? get walletRaw => _secureData[walletKey];

  /// Returns a detached validated copy.
  Map<String, dynamic> get walletSnapshot {
    return _decodeWallet(jsonEncode(_checkedWallet()));
  }

  static Future<EducationStore> open({
    SharedPreferences? preferences,
    SecureLocalCipher? cipher,
    @visibleForTesting Future<bool> Function(String key)? removePreference,
  }) async {
    final store = EducationStore(
      preferences ?? await SharedPreferences.getInstance(),
      cipher: cipher ?? secureCipherOverride ?? const AndroidKeystoreCipher(),
      removePreference: removePreference,
    );

    await store._initializeSecureData();

    try {
      await store.refundInterruptedRequests();
    } on Object {
      // Do not allow a new request while startup refunds are unresolved.
      store._walletError ??=
          'بازیابی درخواست‌های قطع‌شده کامل نشد. '
          'برای جلوگیری از تغییر نادرست موجودی، '
          'کیف پول فعلاً در دسترس نیست. '
          'برنامه را دوباره باز کن.';
    }

    store._initialized = true;

    return store;
  }

  void _emitChange() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _initializeSecureData() async {
    for (final key in [...workspaceKeys, walletKey]) {
      try {
        final stored = prefs.getString(key);

        if (stored == null) continue;

        final String plaintext;

        if (stored.startsWith(encryptedPrefix)) {
          plaintext = await cipher.decrypt(stored, key: key);
        } else {
          // Validate legacy plaintext before replacing its stored envelope.
          if (key == walletKey) {
            _decodeWallet(stored);
          } else {
            _validateWorkspacePayload(key, stored);
          }

          final encrypted = await cipher.encrypt(stored, key: key);

          if (await cipher.decrypt(encrypted, key: key) != stored) {
            throw const LocalDataException(
              'اعتبارسنجی رمزنگاری اطلاعات قدیمی ناموفق بود.',
            );
          }

          if (!await prefs.setString(key, encrypted)) {
            throw const LocalDataException(
              'مهاجرت امن اطلاعات ذخیره نشد؛ '
              'داده قبلی حفظ شد.',
            );
          }

          plaintext = stored;
        }

        // Validate decrypted data too, before making it readable.
        if (key == walletKey) {
          _decodeWallet(plaintext);
        } else {
          _validateWorkspacePayload(key, plaintext);
        }

        _secureData[key] = plaintext;
      } on Object {
        _secureData.remove(key);

        if (key == walletKey) {
          _walletError =
              'کیف پول خوانده یا رمزگشایی نشد؛ '
              'برای جلوگیری از تغییر موجودی پرها، '
              'داده قبلی بازنویسی نمی‌شود.';
        } else {
          _dataErrors[key] =
              'اطلاعات خوانده یا رمزگشایی نشد؛ '
              'برای جلوگیری از بازنویسی، '
              'داده قبلی حفظ شد.';
        }
      }
    }

    if (_walletError != null) return;

    try {
      _wallet = _decodeWallet(_secureData[walletKey]);

      // Only a genuinely absent wallet receives the first-install grant.
      // containsKey also prevents replacing a value of an unexpected type.
      if (_secureData[walletKey] == null && !prefs.containsKey(walletKey)) {
        await _writeSecure(walletKey, jsonEncode(_wallet));
      }
    } on Object {
      _walletError =
          'اطلاعات کیسه پرها خوانده یا ذخیره نشد. '
          'برای جلوگیری از دست رفتن موجودی، '
          'داده قبلی بازنویسی نمی‌شود.';
    }
  }

  void _ensureKnownStorageKey(String key) {
    if (key != walletKey && !workspaceKeys.contains(key)) {
      throw const LocalDataException('کلید ذخیره‌سازی ناشناخته است.');
    }
  }

  void _validateWorkspacePayload(String key, String plaintext) {
    _ensureKnownStorageKey(key);

    if (key == walletKey) return;

    try {
      final value = jsonDecode(plaintext);

      // Keep workspace validation aligned with the backup schema.
      WorkspaceBackup.encode({key: value}, DateTime.now());
    } on BackupFormatException catch (error) {
      throw LocalDataException(error.message);
    } on FormatException {
      throw const LocalDataException(
        'ساختار اطلاعاتی که قرار است ذخیره شود معتبر نیست.',
      );
    }
  }

  Future<void> _writeSecure(String key, String plaintext) async {
    _ensureKnownStorageKey(key);

    if (_dataErrors.containsKey(key)) {
      throw LocalDataException(_dataErrors[key]!);
    }

    if (key == walletKey) {
      if (_walletError != null) {
        throw LocalDataException(_walletError!);
      }

      _decodeWallet(plaintext);
    } else {
      _validateWorkspacePayload(key, plaintext);
    }

    final encrypted = await cipher.encrypt(plaintext, key: key);

    if (await cipher.decrypt(encrypted, key: key) != plaintext) {
      throw const LocalDataException(
        'اعتبارسنجی رمزنگاری اطلاعات ناموفق بود؛ '
        'داده قبلی حفظ شد.',
      );
    }

    if (!await prefs.setString(key, encrypted)) {
      throw const LocalDataException(
        'ذخیره امن اطلاعات انجام نشد. '
        'داده قبلی حفظ شد.',
      );
    }

    _secureData[key] = plaintext;
  }

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());

    // A failed operation must not poison the queue.
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});

    return result;
  }

  static Map<String, dynamic> _emptyWallet() {
    return {
      'version': currentWalletVersion,
      'credits': 5,
      'successful_uses': 0,
      'purchase_tokens': <String, dynamic>{},
      'requests': <String, dynamic>{},
      'transactions': <Map<String, dynamic>>[
        {
          'id': 'welcome-credits-v1',
          'kind': 'bonus',
          'amount': 5,
          'title': 'هدیه نخست · ۵ پر سیمرغ',
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'status': 'completed',
        },
      ],
    };
  }

  static int _nonNegativeInt(Object? value) {
    if (value is! int || value < 0 || value > maxCounterValue) {
      throw const FormatException('Invalid counter');
    }

    return value;
  }

  static String _string(Object? value, int limit) {
    if (value is! String || value.length > limit) {
      throw const FormatException('Invalid string');
    }

    return value;
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is! Map) {
      throw const FormatException('Invalid object');
    }

    final result = <String, dynamic>{};

    for (final entry in value.entries) {
      result[_string(entry.key, 512)] = entry.value;
    }

    return result;
  }

  static bool _hasInvalidIdCharacters(String value) {
    return value.contains(RegExp(r'[\x00-\x1F\x7F]'));
  }

  static String _storedId(Object? value, {int limit = 160}) {
    final id = _string(value, limit);

    if (id.trim().isEmpty || _hasInvalidIdCharacters(id)) {
      throw const FormatException('Invalid stored ID');
    }

    return id;
  }

  /// Decodes legacy wallets without resetting stored balances or tokens.
  ///
  /// Existing legacy versions remain legacy so remaining free uses are
  /// not accidentally removed by a format-only migration.
  static Map<String, dynamic> _decodeWallet(String? raw) {
    if (raw == null) return _emptyWallet();

    if (utf8.encode(raw).length > maxWalletBytes) {
      throw const FormatException('Wallet too large');
    }

    final source = _map(jsonDecode(raw));

    final version = _nonNegativeInt(source['version'] ?? 1);

    if (version < 1 || version > currentWalletVersion) {
      throw const FormatException('Unsupported wallet version');
    }

    final result = <String, dynamic>{
      'version': version,
      'credits': _nonNegativeInt(source['credits'] ?? 0),
      'successful_uses': _nonNegativeInt(source['successful_uses'] ?? 0),
    };

    final tokens = <String, dynamic>{};
    final oldTokens = source['purchase_tokens'];

    if (oldTokens is List) {
      for (final token in oldTokens) {
        final id = _storedId(token, limit: 512);

        tokens[id] = {'productId': 'legacy', 'credits': 0};
      }
    } else if (oldTokens != null) {
      final tokenMap = _map(oldTokens);

      for (final entry in tokenMap.entries) {
        final id = _storedId(entry.key, limit: 512);
        final item = _map(entry.value);

        tokens[id] = {
          'productId': _storedId(item['productId'], limit: 100),
          'credits': _nonNegativeInt(item['credits']),
          if (item['createdAt'] != null)
            'createdAt': _string(item['createdAt'], 40),
        };
      }
    }

    result['purchase_tokens'] = tokens;

    final requests = <String, dynamic>{};

    if (source['requests'] != null) {
      final requestMap = _map(source['requests']);

      for (final entry in requestMap.entries) {
        final id = _storedId(entry.key);
        final item = _map(entry.value);

        final status = _string(item['status'], 20);
        final charge = _string(item['charge'], 20);

        if (!{'pending', 'completed', 'refunded'}.contains(status) ||
            !{'free', 'credit'}.contains(charge)) {
          throw const FormatException('Invalid request state');
        }

        final question = _string(item['question'], maxQuestionLength);

        if (question.trim().isEmpty) {
          throw const FormatException('Empty stored question');
        }

        final request = <String, dynamic>{
          'question': question,
          'status': status,
          'charge': charge,
          'createdAt': _string(item['createdAt'], 40),
          if (item['attempt'] != null)
            'attempt': _nonNegativeInt(item['attempt']),
          if (item['transactionId'] != null)
            'transactionId': _storedId(item['transactionId'], limit: 512),
          if (item['answer'] != null)
            'answer': _string(item['answer'], maxAnswerLength),
        };

        if (request['attempt'] != null && (request['attempt'] as int) < 1) {
          throw const FormatException('Invalid request attempt');
        }

        if (status == 'completed') {
          final answer = request['answer'];

          if (answer is! String || answer.trim().isEmpty) {
            throw const FormatException('Missing saved answer');
          }
        }

        requests[id] = request;
      }
    }

    result['requests'] = requests;

    final transactions = <Map<String, dynamic>>[];
    final oldTransactions = source['transactions'];

    if (oldTransactions != null) {
      if (oldTransactions is! List) {
        throw const FormatException('Invalid ledger');
      }

      for (final Object? value in oldTransactions) {
        final item = _map(value);

        final kind = _string(item['kind'], 20);
        final status = _string(item['status'], 20);

        if (!{'purchase', 'ai', 'refund', 'bonus'}.contains(kind) ||
            !{'pending', 'completed', 'refunded'}.contains(status)) {
          throw const FormatException('Invalid transaction');
        }

        transactions.add({
          'id': _storedId(item['id'], limit: 512),
          'kind': kind,
          'amount': _nonNegativeInt(item['amount']),
          'title': _string(item['title'], 160),
          'createdAt': _string(item['createdAt'], 40),
          'status': status,
        });
      }
    }

    result['transactions'] = transactions;

    return result;
  }

  Map<String, dynamic> _checkedWallet() {
    if (_walletError != null) {
      throw LocalDataException(_walletError!);
    }

    return _wallet;
  }

  int get credits {
    if (_walletError != null) return 0;
    return _wallet['credits'] as int;
  }

  /// Public vocabulary; persisted field remains `credits`.
  int get feathers => credits;

  int get successfulAiUses {
    if (_walletError != null) return 0;
    return _wallet['successful_uses'] as int;
  }

  int get freeAiUsesRemaining {
    if (_walletError != null || (_wallet['version'] as int? ?? 1) >= 3) {
      return 0;
    }

    final pendingFree = (_wallet['requests'] as Map).values
        .where(
          (Object? item) =>
              item is Map &&
              item['status'] == 'pending' &&
              item['charge'] == 'free',
        )
        .length;

    return (freeUses - successfulAiUses - pendingFree)
        .clamp(0, freeUses)
        .toInt();
  }

  bool get hasActiveAiRequests => _activeRequests.isNotEmpty;

  bool get canUseAi {
    return _walletError == null &&
        (freeAiUsesRemaining > 0 || credits >= questionFeatherCost);
  }

  String? savedAiAnswer(String id) {
    if (_walletError != null) return null;

    final request = (_wallet['requests'] as Map)[id] as Map?;

    final answer = request?['answer'];

    if (request?['status'] == 'completed' && answer is String) {
      return answer;
    }

    return null;
  }

  /// Newest first. Purchase tokens are not trimmed with this display history.
  List<Map<String, dynamic>> get creditHistory {
    if (_walletError != null) return const [];

    return (_wallet['transactions'] as List).reversed
        .take(maxHistoryEntries)
        .map((Object? item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }

  Future<void> _saveWallet(
    Map<String, dynamic> wallet, {
    VoidCallback? afterCommit,
  }) async {
    final raw = jsonEncode(wallet);

    // Commit the validated copy, not a caller-owned mutable reference.
    final validated = _decodeWallet(raw);

    await _writeSecure(walletKey, raw);

    _wallet = validated;
    afterCommit?.call();

    // Active-request state is already consistent when listeners run.
    _emitChange();
  }

  Map<String, dynamic> _copyWallet() {
    return _decodeWallet(jsonEncode(_checkedWallet()));
  }

  String _now() {
    return DateTime.now().toUtc().toIso8601String();
  }

  void _transaction(
    Map<String, dynamic> wallet,
    String id,
    String kind,
    int amount,
    String title,
    String status,
  ) {
    if (amount == 0 && kind != 'ai') return;

    final history = wallet['transactions'] as List;

    history.add({
      'id': id,
      'kind': kind,
      'amount': amount,
      'title': title,
      'createdAt': _now(),
      'status': status,
    });

    if (history.length > maxHistoryEntries) {
      history.removeRange(0, history.length - maxHistoryEntries);
    }
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

    if (requests.length <= maxStoredRequests) return;

    final removableIds = requests.entries
        .where(
          (entry) =>
              entry.value['status'] != 'pending' &&
              !_activeRequests.contains(entry.key),
        )
        .map((entry) => entry.key)
        .toList(growable: false);

    for (final id in removableIds) {
      if (requests.length <= maxStoredRequests) break;
      requests.remove(id);
    }

    if (requests.length > maxStoredRequests) {
      throw const LocalDataException(
        'درخواست‌های در حال انجام بیش از ظرفیت '
        'دفتر محلی هستند. پس از پایان یا بازیابی '
        'آن‌ها دوباره تلاش کن.',
      );
    }
  }

  int _requestAttempt(Map request) {
    return (request['attempt'] as int?) ?? 1;
  }

  void _validateAttempt(int? attempt) {
    if (attempt != null && (attempt < 1 || attempt > maxCounterValue)) {
      throw const LocalDataException('شماره تلاش درخواست معتبر نیست.');
    }
  }

  /// Returns false for a callback belonging to an older attempt.
  ///
  /// Null preserves the legacy API. New callers should always pass attempt.
  bool _matchesAttempt(Map request, int? attempt) {
    return attempt == null || _requestAttempt(request) == attempt;
  }

  void _addRefundCredits(Map<String, dynamic> wallet, int amount) {
    final balance = wallet['credits'] as int;

    if (amount < 0 || balance > maxCounterValue - amount) {
      throw const LocalDataException(
        'بازگشت پر از سقف مجاز کیف پول عبور می‌کند.',
      );
    }

    wallet['credits'] = balance + amount;
  }

  /// Reserves a durable charge before the network call.
  ///
  /// Completed IDs return the saved answer without another charge while
  /// that request remains in the bounded request cache.
  Future<AiReservation> prepareAiRequest({
    required String id,
    required String question,
  }) => _serialized(() async {
    _validateId(id);

    if (question.trim().isEmpty || question.length > maxQuestionLength) {
      throw const LocalDataException(
        'متن درخواست باید بین ۱ تا ۴۰۰۰ نویسه باشد.',
      );
    }

    if (_activeRequests.contains(id)) {
      throw const LocalDataException(
        'این درخواست در حال انجام است. '
        'صبر کن تا پاسخ برسد.',
      );
    }

    final wallet = _copyWallet();
    final requests = wallet['requests'] as Map<String, dynamic>;

    final previous = requests[id] as Map<String, dynamic>?;

    if (previous != null && previous['question'] != question) {
      throw const LocalDataException(
        'شناسه درخواست برای متن دیگری ثبت شده است.',
      );
    }

    if (previous?['status'] == 'pending') {
      throw const LocalDataException(
        'این درخواست قبلاً رزرو شده و '
        'هنوز تعیین‌تکلیف نشده است.',
      );
    }

    if (previous?['status'] == 'completed') {
      return AiReservation(
        cachedAnswer: previous!['answer'] as String,
        usesFreeUse: previous['charge'] == 'free',
        attempt: _requestAttempt(previous),
      );
    }

    var charge =
        previous?['charge'] ?? (freeAiUsesRemaining > 0 ? 'free' : 'credit');

    if (charge == 'free' &&
        previous?['status'] == 'refunded' &&
        freeAiUsesRemaining == 0) {
      charge = 'credit';
    }

    if (charge == 'credit' &&
        (wallet['credits'] as int) < questionFeatherCost) {
      throw const LocalDataException(
        'پر سیمرغ کافی نداری. '
        'برای ادامه، یک بسته پر تهیه کن.',
      );
    }

    final previousAttempt = previous == null ? 0 : _requestAttempt(previous);

    if (previousAttempt >= maxCounterValue) {
      throw const LocalDataException(
        'تعداد تلاش‌های این درخواست '
        'از سقف مجاز عبور کرده است.',
      );
    }

    final attempt = previousAttempt + 1;
    final transactionId = '$id-attempt-$attempt';

    if (charge == 'credit') {
      wallet['credits'] = (wallet['credits'] as int) - questionFeatherCost;
    }

    requests[id] = {
      'question': question,
      'status': 'pending',
      'charge': charge,
      'createdAt': previous?['createdAt'] ?? _now(),
      'attempt': attempt,
      'transactionId': transactionId,
    };

    _transaction(
      wallet,
      transactionId,
      'ai',
      charge == 'credit' ? questionFeatherCost : 0,
      charge == 'credit'
          ? 'فراخوان سیمرغ · یک پر'
          : 'فراخوان سیمرغ · استفاده رایگان',
      'pending',
    );

    _trimRequests(wallet);

    await _saveWallet(
      wallet,
      afterCommit: () {
        _activeRequests.add(id);
      },
    );

    return AiReservation(usesFreeUse: charge == 'free', attempt: attempt);
  });

  /// Pass the reservation's attempt for stale-callback protection.
  ///
  /// A mismatched attempt is ignored and cannot complete a newer request.
  Future<void> completeAiRequest(String id, String answer, {int? attempt}) =>
      _serialized(() async {
        _validateId(id);
        _validateAttempt(attempt);

        final wallet = _copyWallet();
        final request = (wallet['requests'] as Map)[id] as Map?;

        if (request == null) {
          throw const LocalDataException(
            'وضعیت درخواست یا پاسخ دریافتی معتبر نیست.',
          );
        }

        if (!_matchesAttempt(request, attempt)) return;

        if (request['status'] == 'completed') return;

        if (request['status'] != 'pending' ||
            answer.trim().isEmpty ||
            answer.length > maxAnswerLength) {
          throw const LocalDataException(
            'وضعیت درخواست یا پاسخ دریافتی معتبر نیست.',
          );
        }

        request['status'] = 'completed';
        request['answer'] = answer;

        if (request['charge'] == 'free') {
          final uses = wallet['successful_uses'] as int;

          if (uses >= maxCounterValue) {
            throw const LocalDataException(
              'شمارنده استفاده از سقف مجاز عبور کرده است.',
            );
          }

          wallet['successful_uses'] = uses + 1;
        }

        _markTransaction(
          wallet,
          (request['transactionId'] as String?) ?? id,
          'completed',
        );

        // Keep the active lock until the durable write succeeds.
        await _saveWallet(
          wallet,
          afterCommit: () {
            _activeRequests.remove(id);
          },
        );
      });

  /// Idempotently refunds a pending request.
  ///
  /// Pass the reservation's attempt for stale-callback protection.
  Future<void> refundAiRequest(String id, {int? attempt}) =>
      _serialized(() async {
        _validateId(id);
        _validateAttempt(attempt);

        final wallet = _copyWallet();
        final request = (wallet['requests'] as Map)[id] as Map?;

        if (request == null ||
            !_matchesAttempt(request, attempt) ||
            request['status'] != 'pending') {
          return;
        }

        request['status'] = 'refunded';

        final amount = request['charge'] == 'credit' ? questionFeatherCost : 0;

        if (amount > 0) {
          _addRefundCredits(wallet, amount);
        }

        final transactionId = (request['transactionId'] as String?) ?? id;

        _markTransaction(wallet, transactionId, 'refunded');

        _transaction(
          wallet,
          '$transactionId-refund',
          'refund',
          amount,
          'بازگشت یک پر سیمرغ · درخواست ناموفق',
          'completed',
        );

        await _saveWallet(
          wallet,
          afterCommit: () {
            _activeRequests.remove(id);
          },
        );
      });

  /// Refunds a completed call whose response cannot be used by the app.
  ///
  /// Idempotent. Pass the reservation's attempt to avoid refunding a newer
  /// completed attempt after an older response fails validation.
  Future<void> refundInvalidAiResponse(String id, {int? attempt}) =>
      _serialized(() async {
        _validateId(id);
        _validateAttempt(attempt);

        final wallet = _copyWallet();
        final requests = wallet['requests'] as Map<String, dynamic>;

        final request = requests[id] as Map<String, dynamic>?;

        if (request == null ||
            !_matchesAttempt(request, attempt) ||
            request['status'] != 'completed') {
          return;
        }

        request['status'] = 'refunded';
        request.remove('answer');

        final amount = request['charge'] == 'credit' ? questionFeatherCost : 0;

        if (amount > 0) {
          _addRefundCredits(wallet, amount);
        } else if (request['charge'] == 'free') {
          wallet['successful_uses'] = ((wallet['successful_uses'] as int) - 1)
              .clamp(0, maxCounterValue)
              .toInt();
        }

        final transactionId = (request['transactionId'] as String?) ?? id;

        _markTransaction(wallet, transactionId, 'refunded');

        _transaction(
          wallet,
          '$transactionId-invalid-refund',
          'refund',
          amount,
          'بازگشت پر · پاسخ ساختاری نامعتبر',
          'completed',
        );

        await _saveWallet(
          wallet,
          afterCommit: () {
            _activeRequests.remove(id);
          },
        );
      });

  /// Refunds persisted pending requests not owned by this running instance.
  ///
  /// Safe to invoke again while other requests are active: their IDs are
  /// excluded from startup recovery.
  Future<void> refundInterruptedRequests() => _serialized(() async {
    if (_walletError != null) return;

    final pending = (_wallet['requests'] as Map).entries
        .where(
          (entry) =>
              entry.value['status'] == 'pending' &&
              !_activeRequests.contains(entry.key),
        )
        .map((entry) => entry.key.toString())
        .toList(growable: false);

    if (pending.isEmpty) return;

    final wallet = _copyWallet();

    for (final id in pending) {
      final request = (wallet['requests'] as Map)[id] as Map;

      request['status'] = 'refunded';

      final amount = request['charge'] == 'credit' ? questionFeatherCost : 0;

      if (amount > 0) {
        // Accumulate against the working copy.
        _addRefundCredits(wallet, amount);
      }

      final transactionId = (request['transactionId'] as String?) ?? id;

      _markTransaction(wallet, transactionId, 'refunded');

      _transaction(
        wallet,
        '$transactionId-refund',
        'refund',
        amount,
        'بازگشت پر سیمرغ پس از بسته شدن برنامه',
        'completed',
      );
    }

    _trimRequests(wallet);

    await _saveWallet(wallet);
  });

  /// Compatibility entry point.
  /// New integrations should use the reservation API.
  Future<bool> recordSuccessfulAiUse({String? requestId}) => _serialized(
    () async {
      final id = requestId ?? 'legacy-${DateTime.now().microsecondsSinceEpoch}';

      _validateId(id);

      final wallet = _copyWallet();
      final requests = wallet['requests'] as Map<String, dynamic>;

      if (requests.containsKey(id)) return false;

      final free = freeAiUsesRemaining > 0;

      if (!free && (wallet['credits'] as int) < questionFeatherCost) {
        return false;
      }

      if (free) {
        final uses = wallet['successful_uses'] as int;

        if (uses >= maxCounterValue) {
          throw const LocalDataException(
            'شمارنده استفاده از سقف مجاز عبور کرده است.',
          );
        }

        wallet['successful_uses'] = uses + 1;
      } else {
        wallet['credits'] = (wallet['credits'] as int) - questionFeatherCost;
      }

      requests[id] = {
        'question': 'درخواست ثبت‌شده',
        'status': 'completed',
        'charge': free ? 'free' : 'credit',
        'createdAt': _now(),
        'attempt': 1,
        'transactionId': id,
        'answer': 'پاسخ دریافت شده',
      };

      _transaction(
        wallet,
        id,
        'ai',
        free ? 0 : questionFeatherCost,
        free ? 'فراخوان سیمرغ · استفاده رایگان' : 'فراخوان سیمرغ · یک پر',
        'completed',
      );

      _trimRequests(wallet);

      await _saveWallet(wallet);

      return true;
    },
  );

  /// Records a purchase already verified by the billing layer.
  ///
  /// This method validates local catalog consistency, NOT purchase authenticity.
  /// A trusted purchase-verification boundary must run before this method.
  ///
  /// Returns false for an already-credited matching token. A conflicting
  /// product/amount for an existing token raises an error.
  Future<bool> grantProduct({
    required String productId,
    required String purchaseToken,
    required int creditsToAdd,
  }) => _serialized(() async {
    _validateId(purchaseToken, limit: 512);

    final product = CreditCatalog.byId(productId);

    if (product == null ||
        product.credits <= 0 ||
        product.credits != creditsToAdd) {
      throw const LocalDataException('بسته پر یا تعداد پر آن معتبر نیست.');
    }

    final wallet = _copyWallet();
    final tokens = wallet['purchase_tokens'] as Map<String, dynamic>;

    final previous = tokens[purchaseToken];

    if (previous != null) {
      final existing = _map(previous);

      // Legacy wallets retained token IDs without purchase details.
      if (existing['productId'] == 'legacy') {
        return false;
      }

      if (existing['productId'] != productId ||
          existing['credits'] != creditsToAdd) {
        throw const LocalDataException(
          'این شناسه خرید قبلاً با بسته دیگری '
          'ثبت شده است؛ برای جلوگیری از تغییر '
          'نادرست موجودی، خرید نهایی نشد.',
        );
      }

      return false;
    }

    final balance = wallet['credits'] as int;

    if (balance > maxCounterValue - creditsToAdd) {
      throw const LocalDataException('موجودی کیف پول از سقف مجاز عبور می‌کند.');
    }

    tokens[purchaseToken] = {
      'productId': productId,
      'credits': creditsToAdd,
      'createdAt': _now(),
    };

    wallet['credits'] = balance + creditsToAdd;

    _transaction(
      wallet,
      'purchase-${tokens.length}',
      'purchase',
      creditsToAdd,
      product.title,
      'completed',
    );

    // Tokens are deliberately never pruned with display history.
    // If the complete wallet exceeds its size limit, fail closed.
    await _saveWallet(wallet);

    return true;
  });

  static void _validateId(String value, {int limit = 160}) {
    if (value.trim().isEmpty ||
        value.length > limit ||
        _hasInvalidIdCharacters(value)) {
      throw const LocalDataException('شناسه محلی معتبر نیست.');
    }
  }

  Map<String, dynamic>? _readObject(String key) {
    _ensureKnownStorageKey(key);

    if (!WorkspaceBackup.objectKeys.contains(key)) {
      throw const LocalDataException(
        'این بخش برای خواندن به‌صورت شیء تعریف نشده است.',
      );
    }

    if (_dataErrors.containsKey(key)) return null;

    final raw = _secureData[key];

    if (raw == null) return null;

    try {
      _validateWorkspacePayload(key, raw);
      return _map(jsonDecode(raw));
    } on Object {
      _dataErrors[key] =
          'اطلاعات قبلی قابل خواندن نیست '
          'و بازنویسی نشده است.';
      return null;
    }
  }

  Map<String, dynamic>? get profile {
    return _readObject('edu.profile');
  }

  Future<void> saveProfile(Map<String, dynamic> value) {
    return _writeMap('edu.profile', value);
  }

  Future<void> _writeMap(String key, Map<String, dynamic> value) {
    // Capture caller-owned mutable data before joining the async queue.
    final raw = jsonEncode(value);

    return _serialized(() async {
      _ensureKnownStorageKey(key);

      if (!WorkspaceBackup.objectKeys.contains(key)) {
        throw const LocalDataException(
          'این بخش برای ذخیره‌سازی به‌صورت شیء '
          'تعریف نشده است.',
        );
      }

      if (_dataErrors.containsKey(key)) {
        throw LocalDataException(_dataErrors[key]!);
      }

      await _writeSecure(key, raw);

      _emitChange();
    });
  }

  List<Map<String, dynamic>> readList(String key) {
    _ensureKnownStorageKey(key);

    if (!WorkspaceBackup.listKeys.contains(key)) {
      throw const LocalDataException(
        'این بخش برای خواندن به‌صورت فهرست تعریف نشده است.',
      );
    }

    if (_dataErrors.containsKey(key)) return [];

    final raw = _secureData[key];

    if (raw == null) return [];

    try {
      _validateWorkspacePayload(key, raw);

      final value = jsonDecode(raw);

      if (value is! List) {
        throw const FormatException('Expected list');
      }

      return value.map(_map).toList();
    } on Object {
      _dataErrors[key] =
          'اطلاعات قبلی قابل خواندن نیست '
          'و بازنویسی نشده است.';
      return [];
    }
  }

  Future<void> writeList(String key, List<Map<String, dynamic>> value) {
    final raw = jsonEncode(value);

    return _serialized(() async {
      _ensureKnownStorageKey(key);

      if (!WorkspaceBackup.listKeys.contains(key)) {
        throw const LocalDataException(
          'این بخش برای ذخیره‌سازی به‌صورت فهرست '
          'تعریف نشده است.',
        );
      }

      if (_dataErrors.containsKey(key)) {
        throw LocalDataException(_dataErrors[key]!);
      }

      await _writeSecure(key, raw);

      _emitChange();
    });
  }

  Future<void> _mutateList(
    String key,
    List<Map<String, dynamic>> Function(List<Map<String, dynamic>>) update,
  ) => _serialized(() async {
    _ensureKnownStorageKey(key);

    if (!WorkspaceBackup.listKeys.contains(key)) {
      throw const LocalDataException(
        'این بخش برای تغییر به‌صورت فهرست '
        'تعریف نشده است.',
      );
    }

    if (_dataErrors.containsKey(key)) {
      throw LocalDataException(_dataErrors[key]!);
    }

    final current = readList(key);

    // Reading may discover a previously unknown schema error.
    if (_dataErrors.containsKey(key)) {
      throw LocalDataException(_dataErrors[key]!);
    }

    final next = update(current);

    await _writeSecure(key, jsonEncode(next));

    _emitChange();
  });

  Map<String, dynamic> _detachedMap(Map<String, dynamic> value) {
    return _map(jsonDecode(jsonEncode(value)));
  }

  List<Map<String, dynamic>> get tasks {
    return readList('edu.tasks');
  }

  Future<void> addTask(Map<String, dynamic> value) {
    final snapshot = _detachedMap(value);

    return _mutateList('edu.tasks', (all) => [snapshot, ...all]);
  }

  Future<void> toggleTask(String id) {
    _validateId(id, limit: 512);

    return _mutateList('edu.tasks', (all) {
      for (final item in all) {
        if (item['id'] == id) {
          final completed = item['done'] != true;

          item['done'] = completed;

          if (completed) {
            item['completedAt'] = _now();
          } else {
            item.remove('completedAt');
          }
        }
      }

      return all;
    });
  }

  Future<void> deleteTask(String id) {
    return _mutateList(
      'edu.tasks',
      (all) => all.where((item) => item['id'] != id).toList(),
    );
  }

  List<Map<String, dynamic>> get exams {
    return readList('edu.exams');
  }

  Future<void> addExam(Map<String, dynamic> value) {
    final snapshot = _detachedMap(value);

    return _mutateList('edu.exams', (all) => [snapshot, ...all]);
  }

  Future<void> deleteExam(String id) {
    return _mutateList(
      'edu.exams',
      (all) => all.where((item) => item['id'] != id).toList(),
    );
  }

  List<Map<String, dynamic>> get cards {
    return readList('edu.cards');
  }

  Future<void> addCard(Map<String, dynamic> value) {
    final snapshot = _detachedMap(value);

    return _mutateList('edu.cards', (all) => [snapshot, ...all]);
  }

  Future<void> updateCard(Map<String, dynamic> value) {
    final snapshot = _detachedMap(value);

    return _mutateList('edu.cards', (all) {
      final index = all.indexWhere((item) => item['id'] == snapshot['id']);

      if (index >= 0) {
        all[index] = snapshot;
      }

      return all;
    });
  }

  Future<void> deleteCard(String id) {
    return _mutateList(
      'edu.cards',
      (all) => all.where((item) => item['id'] != id).toList(),
    );
  }

  List<Map<String, dynamic>> get teachingSessions {
    return readList('edu.teaching.sessions');
  }

  Future<void> saveTeachingSessions(List<Map<String, dynamic>> value) {
    return writeList(
      'edu.teaching.sessions',
      value.length <= 30 ? value : value.sublist(value.length - 30),
    );
  }

  List<Map<String, dynamic>> get messages {
    return readList('edu.messages');
  }

  Future<void> saveMessages(List<Map<String, dynamic>> value) {
    return writeList(
      'edu.messages',
      value.length <= 80 ? value : value.sublist(value.length - 80),
    );
  }

  List<Map<String, dynamic>> get reports {
    return readList('edu.reports');
  }

  Future<void> addReport(Map<String, dynamic> value) {
    final snapshot = _detachedMap(value);

    return _mutateList(
      'edu.reports',
      (all) => [snapshot, ...all].take(50).toList(),
    );
  }

  Future<void> deleteReport(String id) {
    return _mutateList(
      'edu.reports',
      (all) => all.where((item) => item['id'] != id).toList(),
    );
  }

  Map<String, dynamic>? get careerDraft {
    return _readObject('edu.career.draft');
  }

  Future<void> saveCareerDraft(Map<String, dynamic> value) {
    return _writeMap('edu.career.draft', value);
  }

  List<Map<String, dynamic>> get deadlines {
    return readList('edu.deadlines');
  }

  Future<void> addDeadline(Map<String, dynamic> value) {
    final snapshot = _detachedMap(value);

    return _mutateList('edu.deadlines', (all) => [snapshot, ...all]);
  }

  Future<void> deleteDeadline(String id) {
    return _mutateList(
      'edu.deadlines',
      (all) => all.where((item) => item['id'] != id).toList(),
    );
  }

  /// Applies SM-2 scoring and saves the resulting card.
  Future<void> reviewCard(String id, int quality, DateTime now) =>
      _mutateList('edu.cards', (all) {
        final index = all.indexWhere((card) => card['id'] == id);

        if (index < 0) {
          throw const LocalDataException('فلش‌کارت پیدا نشد.');
        }

        all[index] = applyCardReview(all[index], quality, now);

        return all;
      });

  /// Stores assigned dates and supplied audit reasons.
  Future<void> applyPlanDates(
    Map<String, String> assignments, {
    List<PlanChange> changes = const [],
    DateTime? now,
  }) {
    final assignmentSnapshot = Map<String, String>.from(assignments);

    // Capture only the immutable values needed by the queued operation.
    final reasonsById = <String, String>{
      for (final change in changes) change.taskId: change.reason,
    };

    final changedAt = (now ?? DateTime.now()).toIso8601String();

    return _mutateList('edu.tasks', (all) {
      return [
        for (final task in all)
          if (assignmentSnapshot.containsKey(task['id'].toString()))
            _applyPlanDate(
              task,
              assignmentSnapshot[task['id'].toString()]!,
              reasonsById[task['id'].toString()],
              changedAt,
            )
          else
            task,
      ];
    });
  }

  Map<String, dynamic> _applyPlanDate(
    Map<String, dynamic> task,
    String newDate,
    String? reason,
    String changedAt,
  ) {
    if (reason == null) {
      return {...task, 'dueDate': newDate};
    }

    final history = task['planHistory'] is List
        ? (task['planHistory'] as List)
              .whereType<Map>()
              .map((entry) => Map<String, dynamic>.from(entry))
              .toList()
        : <Map<String, dynamic>>[];

    history.add({
      'previousDate': task['dueDate'],
      'newDate': newDate,
      'reason': reason,
      'changedAt': changedAt,
    });

    if (history.length > 100) {
      history.removeRange(0, history.length - 100);
    }

    return {...task, 'dueDate': newDate, 'planHistory': history};
  }

  /// Exports plaintext study data. Never includes wallet data.
  ///
  /// Callers must handle the exported file as sensitive student information.
  Future<String> exportBackup() => _serialized(() async {
    final damaged = _dataErrors.keys
        .where(workspaceKeys.contains)
        .toList(growable: false);

    if (damaged.isNotEmpty) {
      throw const LocalDataException(
        'بخشی از اطلاعات قابل خواندن نیست؛ '
        'برای جلوگیری از ساخت پشتیبان ناقص، '
        'ابتدا بازیابی یا پاک‌سازی امن را انجام بده.',
      );
    }

    final data = <String, Object?>{};

    for (final key in workspaceKeys) {
      final raw = _secureData[key];

      if (raw == null) continue;

      try {
        _validateWorkspacePayload(key, raw);
        data[key] = jsonDecode(raw);
      } on Object {
        _dataErrors[key] =
            'این بخش برای ساخت پشتیبان '
            'قابل خواندن نیست.';

        _emitChange();

        throw LocalDataException(
          'بخش «$key» خوانده نمی‌شود؛ '
          'پشتیبان ناقص ساخته نشد.',
        );
      }
    }

    return WorkspaceBackup.encode(data, DateTime.now());
  });

  Map<String, String?> _snapshotStoredWorkspace() {
    return {for (final key in workspaceKeys) key: prefs.getString(key)};
  }

  Map<String, String?> _snapshotSecureWorkspace() {
    return {for (final key in workspaceKeys) key: _secureData[key]};
  }

  Map<String, String> _snapshotWorkspaceErrors() {
    return {
      for (final entry in _dataErrors.entries)
        if (workspaceKeys.contains(entry.key)) entry.key: entry.value,
    };
  }

  /// Restores exact previous envelopes and in-memory plaintext values.
  ///
  /// Returns keys whose on-disk restoration could not be confirmed.
  Future<List<String>> _rollbackWorkspace({
    required Map<String, String?> previousStored,
    required Map<String, String?> previousSecure,
    required Map<String, String> previousErrors,
    required String failureMessage,
  }) async {
    final rollbackFailures = <String>[];

    for (final key in workspaceKeys) {
      try {
        final original = previousStored[key];

        final restored = original == null
            ? await prefs.remove(key)
            : await prefs.setString(key, original);

        if (!restored) {
          rollbackFailures.add(key);
        }
      } on Object {
        rollbackFailures.add(key);
      }

      final plaintext = previousSecure[key];

      if (plaintext == null) {
        _secureData.remove(key);
      } else {
        _secureData[key] = plaintext;
      }
    }

    _dataErrors.removeWhere((key, _) => workspaceKeys.contains(key));

    _dataErrors.addAll(previousErrors);

    for (final key in rollbackFailures) {
      _secureData.remove(key);
      _dataErrors[key] = failureMessage;
    }

    return rollbackFailures;
  }

  /// Replaces the study workspace with a validated backup.
  ///
  /// Wallet data is never touched. Caught failures trigger best-effort
  /// rollback; process death midway is not an atomic transaction.
  Future<int> importBackup(String raw) => _serialized(() async {
    final data = WorkspaceBackup.decode(raw);

    final previousStored = _snapshotStoredWorkspace();
    final previousSecure = _snapshotSecureWorkspace();
    final previousErrors = _snapshotWorkspaceErrors();

    _dataErrors.removeWhere((key, _) => workspaceKeys.contains(key));

    try {
      for (final key in workspaceKeys) {
        final value = data[key];

        if (value == null) {
          if (!await _removePreference(key)) {
            throw const LocalDataException('بازیابی انجام نشد.');
          }

          _secureData.remove(key);
        } else {
          await _writeSecure(key, jsonEncode(value));
        }
      }
    } on Object {
      final rollbackFailures = await _rollbackWorkspace(
        previousStored: previousStored,
        previousSecure: previousSecure,
        previousErrors: previousErrors,
        failureMessage:
            'بازگردانی این بخش پس از خطای '
            'واردسازی کامل نشد.',
      );

      if (rollbackFailures.isNotEmpty) {
        _emitChange();

        throw const LocalDataException(
          'بازیابی ناموفق بود و بازگردانی کامل '
          'داده‌های قبلی تأیید نشد. '
          'از پاک‌سازی یا بازنویسی دوباره خودداری کن '
          'و برای بررسی داده‌های محلی اقدام کن.',
        );
      }

      rethrow;
    }

    _dataErrors.removeWhere((key, _) => workspaceKeys.contains(key));

    _emitChange();

    return data.length;
  });

  /// Deletes only the study workspace.
  ///
  /// Wallet balance, purchase tokens and financial history are not deleted.
  /// Caught failures trigger best-effort rollback of all workspace keys.
  Future<void> clear() => _serialized(() async {
    final previousStored = _snapshotStoredWorkspace();
    final previousSecure = _snapshotSecureWorkspace();
    final previousErrors = _snapshotWorkspaceErrors();

    try {
      for (final key in workspaceKeys) {
        if (!await _removePreference(key)) {
          throw const LocalDataException(
            'حذف کامل اطلاعات انجام نشد. '
            'بازگردانی داده‌های قبلی انجام می‌شود؛ '
            'دوباره تلاش کن.',
          );
        }
      }
    } on Object {
      final rollbackFailures = await _rollbackWorkspace(
        previousStored: previousStored,
        previousSecure: previousSecure,
        previousErrors: previousErrors,
        failureMessage:
            'بازگردانی این بخش پس از خطای '
            'حذف کامل نشد.',
      );

      if (rollbackFailures.isNotEmpty) {
        _emitChange();

        throw const LocalDataException(
          'حذف اطلاعات ناموفق بود و بازگردانی کامل '
          'داده‌های قبلی تأیید نشد. '
          'از پاک‌سازی یا بازنویسی دوباره خودداری کن '
          'و برای بررسی داده‌های محلی اقدام کن.',
        );
      }

      rethrow;
    }

    for (final key in workspaceKeys) {
      _secureData.remove(key);
      _dataErrors.remove(key);
    }

    _emitChange();
  });
}

class CreditProduct {
  const CreditProduct(
    this.id,
    this.title,
    this.credits,
    this.description, {
    this.purchasedCredits = 0,
    this.bonusCredits = 0,
  });

  final String id;
  final String title;
  final String description;

  /// Total delivered balance, including pack bonuses.
  final int credits;

  final int purchasedCredits;
  final int bonusCredits;

  /// Public vocabulary; storage remains compatible with `credits`.
  int get feathers => credits;
}

/// Existing SKU IDs retained.
///
/// Confirm SKU identity AND delivered quantities against the Bazaar panel
/// before enabling checkout. A public key alone does not validate a catalog.
class CreditCatalog {
  static const products = [
    CreditProduct(
      'credit_10',
      'بسته برنزی · ۱۰۰ پر',
      100,
      '۱۰۰ پر سیمرغ',
      purchasedCredits: 100,
    ),
    CreditProduct(
      'credit_35',
      'بسته نقره‌ای · ۲۶۵ پر',
      265,
      '۲۵۰ پر خرید + ۱۵ پر هدیه',
      purchasedCredits: 250,
      bonusCredits: 15,
    ),
    CreditProduct(
      'credit_90',
      'بسته طلایی · ۵۵۰ پر',
      550,
      '۵۰۰ پر خرید + ۵۰ پر هدیه',
      purchasedCredits: 500,
      bonusCredits: 50,
    ),
  ];

  static CreditProduct? byId(String id) {
    for (final product in products) {
      if (product.id == id) return product;
    }

    return null;
  }
}
