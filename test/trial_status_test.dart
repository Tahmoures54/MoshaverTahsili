import 'package:flutter_test/flutter_test.dart';
import 'package:smart_mechanic/services/local_first_store.dart';

void main() {
  group('TrialStatus', () {
    final startedAt = DateTime.utc(2026, 1, 1);

    test('keeps the second free diagnosis as the last trial use', () {
      final status = TrialStatus.evaluate(
        startedAt: startedAt,
        completedDiagnoses: 1,
        now: startedAt.add(const Duration(days: 30)),
      );
      expect(status.shouldShowPlans, isFalse);
      expect(status.elapsedDays, 30);
    });

    test('requires a purchase after two successful diagnoses', () {
      final status = TrialStatus.evaluate(
        startedAt: startedAt,
        completedDiagnoses: 2,
        now: startedAt.add(const Duration(days: 1)),
      );
      expect(status.shouldShowPlans, isTrue);
    });

    test('does not grant extra free diagnoses based on elapsed days', () {
      final status = TrialStatus.evaluate(
        startedAt: startedAt,
        completedDiagnoses: 1,
        now: startedAt.add(const Duration(days: 10)),
      );
      expect(status.shouldShowPlans, isFalse);
    });

    test('does not count a future start date as elapsed time', () {
      final status = TrialStatus.evaluate(
        startedAt: startedAt.add(const Duration(days: 1)),
        completedDiagnoses: 0,
        now: startedAt,
      );
      expect(status.elapsedDays, 0);
      expect(status.shouldShowPlans, isFalse);
    });
  });
}
