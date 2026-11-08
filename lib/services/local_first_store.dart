import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local-only profile, trial and diagnostic history for the Cafe Bazaar app.
/// This database is intentionally independent of the web backend.
class LocalFirstStore {
  LocalFirstStore._(this._db);

  final Database _db;

  static Future<LocalFirstStore> open() async {
    final root = await getDatabasesPath();
    final db = await openDatabase(
      p.join(root, 'smart_mechanic_local.db'),
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE app_profile (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            phone TEXT NOT NULL DEFAULT '',
            created_at_ms INTEGER NOT NULL,
            trial_started_at_ms INTEGER NOT NULL,
            completed_diagnoses INTEGER NOT NULL DEFAULT 0,
            credits INTEGER NOT NULL DEFAULT 0,
            golden_until_ms INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE diagnostic_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            car_name TEXT NOT NULL,
            car_year TEXT NOT NULL,
            description TEXT NOT NULL,
            result TEXT NOT NULL,
            created_at_ms INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE local_purchases (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            product_id TEXT NOT NULL,
            purchase_token TEXT NOT NULL UNIQUE,
            purchased_at_ms INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE credit_lots (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            purchase_token TEXT NOT NULL UNIQUE,
            product_id TEXT NOT NULL,
            credits_remaining INTEGER NOT NULL CHECK (credits_remaining >= 0),
            expires_at_ms INTEGER,
            purchased_at_ms INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE saved_cars (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            year TEXT NOT NULL DEFAULT '',
            created_at_ms INTEGER NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE credit_lots (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              purchase_token TEXT NOT NULL UNIQUE,
              product_id TEXT NOT NULL,
              credits_remaining INTEGER NOT NULL CHECK (credits_remaining >= 0),
              expires_at_ms INTEGER,
              purchased_at_ms INTEGER NOT NULL
            )
          ''');
          final rows = await db.query('app_profile', where: 'id = 1', limit: 1);
          if (rows.isNotEmpty) {
            final credits = rows.first['credits'] as int? ?? 0;
            if (credits > 0) {
              await db.insert('credit_lots', {
                'purchase_token': 'legacy-migration',
                'product_id': 'legacy_credits',
                'credits_remaining': credits,
                'expires_at_ms': null,
                'purchased_at_ms': rows.first['created_at_ms'] as int,
              });
            }
          }
        }
      },
    );

    final store = LocalFirstStore._(db);
    await store._ensureProfile();
    return store;
  }

  Future<void> _ensureProfile() async {
    final rows = await _db.query('app_profile', where: 'id = 1', limit: 1);
    if (rows.isNotEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.insert('app_profile', {
      'id': 1,
      'phone': '',
      'created_at_ms': now,
      'trial_started_at_ms': now,
      'completed_diagnoses': 0,
    });
  }

  Future<Map<String, Object?>> get profile async {
    var rows = await _db.query('app_profile', where: 'id = 1', limit: 1);
    if (rows.isEmpty) {
      await _ensureProfile();
      rows = await _db.query('app_profile', where: 'id = 1', limit: 1);
    }
    return rows.first;
  }

  Future<String> get phone async =>
      ((await profile)['phone'] as String?) ?? '';

  Future<void> savePhone(String value) async {
    final phone = value.trim();
    if (!RegExp(r'^09\d{9}$').hasMatch(phone)) {
      throw ArgumentError('شماره موبایل باید با 09 شروع شود و ۱۱ رقم باشد.');
    }
    final current = await profile;
    final updates = <String, Object?>{'phone': phone};
    if (((current['phone'] as String?) ?? '').isEmpty) {
      final now = DateTime.now().millisecondsSinceEpoch;
      updates['created_at_ms'] = now;
      updates['trial_started_at_ms'] = now;
    }
    await _db.update('app_profile', updates, where: 'id = 1');
  }

  /// Sign out of this device without deleting local history or purchased credits.
  Future<void> clearPhone() async {
    await _ensureProfile();
    await _db.update(
      'app_profile',
      {'phone': ''},
      where: 'id = 1',
    );
  }

  Future<DateTime> get trialStartedAt async {
    final value = (await profile)['trial_started_at_ms'] as int;
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  Future<int> get completedDiagnoses async =>
      (await profile)['completed_diagnoses'] as int? ?? 0;

  Future<int> get credits async => _db.transaction((txn) async {
        await _expireCreditLots(txn);
        final rows = await txn.query('app_profile', where: 'id = 1', limit: 1);
        return rows.isEmpty ? 0 : (rows.first['credits'] as int? ?? 0);
      });

  Future<void> _expireCreditLots(DatabaseExecutor txn) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final expired = await txn.query(
      'credit_lots',
      columns: ['credits_remaining'],
      where: 'expires_at_ms IS NOT NULL AND expires_at_ms <= ? AND credits_remaining > 0',
      whereArgs: [now],
    );
    final expiredCredits = expired.fold<int>(
      0,
      (sum, row) => sum + ((row['credits_remaining'] as int?) ?? 0),
    );
    if (expired.isEmpty) return;
    await txn.delete(
      'credit_lots',
      where: 'expires_at_ms IS NOT NULL AND expires_at_ms <= ?',
      whereArgs: [now],
    );
    if (expiredCredits > 0) {
      final rows = await txn.query('app_profile', where: 'id = 1', limit: 1);
      if (rows.isNotEmpty) {
        final current = rows.first['credits'] as int? ?? 0;
        final remaining = current - expiredCredits;
        await txn.update(
          'app_profile',
          {'credits': remaining < 0 ? 0 : remaining},
          where: 'id = 1',
        );
      }
    }
  }

  Future<bool> get isGoldenActive async {
    final until = (await profile)['golden_until_ms'] as int?;
    return until != null && until > DateTime.now().millisecondsSinceEpoch;
  }

  Future<void> grantProduct({
    required String productId,
    required String purchaseToken,
    int creditsToAdd = 0,
    int goldenDays = 0,
  }) async {
    if (productId.trim().isEmpty || purchaseToken.trim().isEmpty) {
      throw ArgumentError('شناسه محصول و توکن خرید الزامی است.');
    }
    await _db.transaction((txn) async {
      final existing = await txn.query(
        'local_purchases',
        where: 'purchase_token = ?',
        whereArgs: [purchaseToken],
        limit: 1,
      );
      if (existing.isNotEmpty) return;
      await txn.insert('local_purchases', {
        'product_id': productId,
        'purchase_token': purchaseToken,
        'purchased_at_ms': DateTime.now().millisecondsSinceEpoch,
      });
      final now = DateTime.now().millisecondsSinceEpoch;
      int? goldExpiry;
      if (goldenDays > 0) {
        final rows = await txn.query('app_profile', where: 'id = 1', limit: 1);
        final current = rows.first['golden_until_ms'] as int?;
        final base = current != null && current > now ? current : now;
        goldExpiry = base + Duration(days: goldenDays).inMilliseconds;
        await txn.update(
          'app_profile',
          {'golden_until_ms': goldExpiry},
          where: 'id = 1',
        );
      }
      if (creditsToAdd > 0) {
        await txn.insert('credit_lots', {
          'purchase_token': purchaseToken,
          'product_id': productId,
          'credits_remaining': creditsToAdd,
          'expires_at_ms': goldExpiry,
          'purchased_at_ms': now,
        });
        await txn.rawUpdate(
          'UPDATE app_profile SET credits = credits + ? WHERE id = 1',
          [creditsToAdd],
        );
      }
    });
  }

  Future<bool> consumeLocalCredit() async {
    return _db.transaction((txn) async {
      await _expireCreditLots(txn);
      final now = DateTime.now().millisecondsSinceEpoch;
      final lots = await txn.query(
        'credit_lots',
        where: 'credits_remaining > 0 AND (expires_at_ms IS NULL OR expires_at_ms > ?)',
        whereArgs: [now],
        orderBy: 'CASE WHEN expires_at_ms IS NULL THEN 1 ELSE 0 END, expires_at_ms ASC, purchased_at_ms ASC',
        limit: 1,
      );
      if (lots.isEmpty) return false;
      final lot = lots.first;
      await txn.rawUpdate(
        'UPDATE credit_lots SET credits_remaining = credits_remaining - 1 WHERE id = ? AND credits_remaining > 0',
        [lot['id']],
      );
      await txn.rawUpdate(
        'UPDATE app_profile SET credits = credits - 1 WHERE id = 1 AND credits > 0',
      );
      return true;
    });
  }

  Future<TrialStatus> get trialStatus async {
    final row = await profile;
    final started = DateTime.fromMillisecondsSinceEpoch(
      row['trial_started_at_ms'] as int,
    );
    final count = row['completed_diagnoses'] as int? ?? 0;
    return TrialStatus.evaluate(
      startedAt: started,
      completedDiagnoses: count,
      now: DateTime.now(),
    );
  }

  /// Call only after a successful, non-empty diagnosis response.
  Future<void> saveDiagnosis({
    required String carName,
    required String carYear,
    required String description,
    required String result,
  }) async {
    final cleanResult = result.trim();
    if (cleanResult.isEmpty) {
      throw ArgumentError('نتیجه خالی را نمی‌توان در تاریخچه ثبت کرد.');
    }

    await _db.transaction((txn) async {
      await _expireCreditLots(txn);
      final rows = await txn.query('app_profile', where: 'id = 1', limit: 1);
      if (rows.isEmpty) throw StateError('پروفایل محلی پیدا نشد.');
      final completed = rows.first['completed_diagnoses'] as int? ?? 0;

      // First two successful diagnoses are free. Every later successful
      // diagnosis must atomically consume one valid credit, even during a
      // gold plan's active period.
      if (completed >= 2) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final lots = await txn.query(
          'credit_lots',
          where: 'credits_remaining > 0 AND (expires_at_ms IS NULL OR expires_at_ms > ?)',
          whereArgs: [now],
          orderBy: 'CASE WHEN expires_at_ms IS NULL THEN 1 ELSE 0 END, expires_at_ms ASC, purchased_at_ms ASC',
          limit: 1,
        );
        if (lots.isEmpty) {
          throw const InsufficientLocalCreditsException();
        }
        final lot = lots.first;
        await txn.rawUpdate(
          'UPDATE credit_lots SET credits_remaining = credits_remaining - 1 WHERE id = ? AND credits_remaining > 0',
          [lot['id']],
        );
        final changed = await txn.rawUpdate(
          'UPDATE app_profile SET credits = credits - 1, completed_diagnoses = completed_diagnoses + 1 WHERE id = 1 AND credits > 0',
        );
        if (changed != 1) {
          throw const InsufficientLocalCreditsException();
        }
      } else {
        await txn.rawUpdate(
          'UPDATE app_profile SET completed_diagnoses = completed_diagnoses + 1 WHERE id = 1',
        );
      }

      await txn.insert('diagnostic_history', {
        'car_name': carName.trim(),
        'car_year': carYear.trim(),
        'description': description.trim(),
        'result': cleanResult,
        'created_at_ms': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  Future<List<Map<String, Object?>>> get history async =>
      _db.query('diagnostic_history', orderBy: 'created_at_ms DESC');

  Future<void> deleteDiagnosis(String id) async {
    final rowId = int.tryParse(id);
    if (rowId == null) return;
    await _db.delete('diagnostic_history', where: 'id = ?', whereArgs: [rowId]);
  }

  Future<void> saveCar({required String name, String year = ''}) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('نام خودرو الزامی است.');
    await _db.insert('saved_cars', {
      'name': cleanName,
      'year': year.trim(),
      'created_at_ms': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, Object?>>> get cars async =>
      _db.query('saved_cars', orderBy: 'created_at_ms DESC');

  Future<void> close() => _db.close();
}

class InsufficientLocalCreditsException implements Exception {
  const InsufficientLocalCreditsException();
}

class TrialStatus {
  const TrialStatus({
    required this.startedAt,
    required this.completedDiagnoses,
    required this.elapsedDays,
    required this.shouldShowPlans,
  });

  final DateTime startedAt;
  final int completedDiagnoses;
  final int elapsedDays;
  final bool shouldShowPlans;

  static TrialStatus evaluate({
    required DateTime startedAt,
    required int completedDiagnoses,
    required DateTime now,
  }) {
    final elapsed = now.difference(startedAt).inDays;
    return TrialStatus(
      startedAt: startedAt,
      completedDiagnoses: completedDiagnoses,
      elapsedDays: elapsed < 0 ? 0 : elapsed,
      shouldShowPlans: completedDiagnoses >= 2,
    );
  }
}
