import 'package:flutter_test/flutter_test.dart';
import 'package:moshaver_tahsili/education/simorgh_teaching_engine.dart';

void main() {
  group('Simorgh teaching engine', () {
    test('requires a topic and starts with a short diagnostic', () {
      expect(() => SimorghTeachingEngine.start(topic: '  '), throwsArgumentError);
      final session = SimorghTeachingEngine.start(
        topic: 'معادله درجه دوم',
        grade: 'متوسطه اول',
      );
      expect(session.stage, SimorghTeachingStage.diagnostic);
      expect(SimorghTeachingEngine.instructionFor(session), contains('حداکثر در سه گام'));
    });

    test('adapts the route after three diagnostic answers', () {
      var session = SimorghTeachingEngine.start(topic: 'کسرها');
      session = SimorghTeachingEngine.recordDiagnostic(session, SimorghAnswerOutcome.correct);
      session = SimorghTeachingEngine.recordDiagnostic(session, SimorghAnswerOutcome.correct);
      session = SimorghTeachingEngine.recordDiagnostic(session, SimorghAnswerOutcome.incorrect);
      expect(session.stage, SimorghTeachingStage.guidedPractice);
      expect(session.diagnosticAccuracy, closeTo(2 / 3, 0.001));
    });

    test('chooses an explanation when diagnostic evidence is weak', () {
      var session = SimorghTeachingEngine.start(topic: 'کسرها');
      for (var i = 0; i < 3; i++) {
        session = SimorghTeachingEngine.recordDiagnostic(
          session,
          SimorghAnswerOutcome.incorrect,
        );
      }
      expect(session.stage, SimorghTeachingStage.explanation);
      session = SimorghTeachingEngine.beginGuidedPractice(session);
      expect(session.stage, SimorghTeachingStage.guidedPractice);
    });

    test('changes explanation after a wrong practice answer', () {
      var session = SimorghTeachingEngine.start(topic: 'توان');
      session = session.copyWith(stage: SimorghTeachingStage.guidedPractice);
      session = SimorghTeachingEngine.recordPractice(
        session: session,
        outcome: SimorghAnswerOutcome.incorrect,
        error: SimorghErrorKind.conceptual,
      );
      expect(session.stage, SimorghTeachingStage.reteach);
      expect(session.lastError, SimorghErrorKind.conceptual);
      expect(session.explanationVariant, 1);
      expect(SimorghTeachingEngine.instructionFor(session), contains('روش توضیح متفاوت'));
      session = SimorghTeachingEngine.finishReteach(session);
      expect(session.stage, SimorghTeachingStage.guidedPractice);
    });

    test('repeats a different explanation when the explanation check is still wrong', () {
      var session = SimorghTeachingEngine.start(topic: 'کسرها').copyWith(
        stage: SimorghTeachingStage.explanation,
      );
      session = SimorghTeachingEngine.recordExplanationCheck(
        session,
        SimorghAnswerOutcome.incorrect,
      );
      expect(session.stage, SimorghTeachingStage.explanation);
      expect(session.explanationVariant, 1);
      final firstInstruction = SimorghTeachingEngine.instructionFor(
        SimorghTeachingSession(topic: 'کسرها', grade: '', stage: SimorghTeachingStage.explanation),
      );
      final alternateInstruction = SimorghTeachingEngine.instructionFor(session);
      expect(alternateInstruction, isNot(firstInstruction));
      expect(alternateInstruction, contains('تشبیه روزمره متفاوت'));
      session = SimorghTeachingEngine.recordExplanationCheck(
        session,
        SimorghAnswerOutcome.correct,
      );
      expect(session.stage, SimorghTeachingStage.guidedPractice);
    });

    test('keeps reteaching until the learner answers the simpler check', () {
      var session = SimorghTeachingSession(
        topic: 'تابع', grade: '', stage: SimorghTeachingStage.reteach,
      );
      session = SimorghTeachingEngine.recordReteachCheck(
        session: session,
        outcome: SimorghAnswerOutcome.incorrect,
        error: SimorghErrorKind.conceptual,
      );
      expect(session.stage, SimorghTeachingStage.reteach);
      expect(session.explanationVariant, 1);
      session = SimorghTeachingEngine.recordReteachCheck(
        session: session,
        outcome: SimorghAnswerOutcome.correct,
      );
      expect(session.stage, SimorghTeachingStage.guidedPractice);
    });

    test('requires transfer evidence before marking learning complete', () {
      var session = SimorghTeachingSession(
        topic: 'تابع',
        grade: 'یازدهم',
        stage: SimorghTeachingStage.masteryCheck,
      );
      session = SimorghTeachingEngine.recordMasteryCheck(
        session: session,
        outcome: SimorghAnswerOutcome.correct,
      );
      session = SimorghTeachingEngine.recordMasteryCheck(
        session: session,
        outcome: SimorghAnswerOutcome.correct,
      );
      session = SimorghTeachingEngine.recordMasteryCheck(
        session: session,
        outcome: SimorghAnswerOutcome.incorrect,
      );
      expect(session.stage, SimorghTeachingStage.completed);
      expect(session.masteryAccuracy, closeTo(2 / 3, 0.001));
    });

    test('returns to reteaching if transfer check is not passed', () {
      var session = SimorghTeachingSession(
        topic: 'تابع',
        grade: '',
        stage: SimorghTeachingStage.masteryCheck,
      );
      for (var i = 0; i < 3; i++) {
        session = SimorghTeachingEngine.recordMasteryCheck(
          session: session,
          outcome: SimorghAnswerOutcome.incorrect,
          error: SimorghErrorKind.prerequisite,
        );
      }
      expect(session.stage, SimorghTeachingStage.reteach);
      expect(session.lastError, SimorghErrorKind.prerequisite);
      expect(session.reteachCount, 1);
    });

    test('does not accept out-of-order transitions', () {
      final session = SimorghTeachingEngine.start(topic: 'هندسه');
      expect(
        () => SimorghTeachingEngine.recordPractice(
          session: session,
          outcome: SimorghAnswerOutcome.correct,
        ),
        throwsStateError,
      );
    });

    test('closes diagnostic after the configured limit', () {
      var session = SimorghTeachingEngine.start(topic: 'علوم');
      for (var i = 0; i < SimorghTeachingEngine.diagnosticQuestionLimit; i++) {
        session = SimorghTeachingEngine.recordDiagnostic(
          session,
          SimorghAnswerOutcome.correct,
        );
      }
      expect(session.diagnosticCount, SimorghTeachingEngine.diagnosticQuestionLimit);
      expect(session.stage, SimorghTeachingStage.guidedPractice);
      expect(
        () => SimorghTeachingEngine.recordDiagnostic(
          session,
          SimorghAnswerOutcome.correct,
        ),
        throwsStateError,
      );
    });
    test('treats partial diagnostic evidence as incomplete, not correct', () {
      var session = SimorghTeachingEngine.start(topic: 'کسرها');
      session = SimorghTeachingEngine.recordDiagnostic(
        session,
        SimorghAnswerOutcome.partial,
      );
      expect(session.diagnosticCount, 1);
      expect(session.diagnosticCorrect, 0);
      expect(session.stage, SimorghTeachingStage.diagnostic);
    });

    test('routes a partially correct practice answer to targeted reteaching', () {
      final session = SimorghTeachingSession(
        topic: 'معادله',
        grade: 'هشتم',
        stage: SimorghTeachingStage.guidedPractice,
      );
      final updated = SimorghTeachingEngine.recordPractice(
        session: session,
        outcome: SimorghAnswerOutcome.partial,
        error: SimorghErrorKind.procedural,
      );
      expect(updated.stage, SimorghTeachingStage.reteach);
      expect(updated.practiceAttempts, 1);
      expect(updated.lastError, SimorghErrorKind.procedural);
      expect(updated.masteryCount, 0);
    });

    test('does not count partial mastery evidence as a fully correct answer', () {
      var session = SimorghTeachingSession(
        topic: 'تابع',
        grade: 'دهم',
        stage: SimorghTeachingStage.masteryCheck,
      );
      session = SimorghTeachingEngine.recordMasteryCheck(
        session: session,
        outcome: SimorghAnswerOutcome.correct,
      );
      session = SimorghTeachingEngine.recordMasteryCheck(
        session: session,
        outcome: SimorghAnswerOutcome.partial,
      );
      session = SimorghTeachingEngine.recordMasteryCheck(
        session: session,
        outcome: SimorghAnswerOutcome.incorrect,
      );
      expect(session.stage, SimorghTeachingStage.reteach);
      expect(session.masteryCorrect, 1);
      expect(session.masteryCount, 3);
    });

    test('completes a full adaptive lesson from diagnosis through reteaching and mastery', () {
      var session = SimorghTeachingEngine.start(
        topic: 'معادله درجه دوم',
        grade: 'دهم',
      );

      // Partial evidence is not counted as correct during diagnosis.
      session = SimorghTeachingEngine.recordDiagnostic(
        session,
        SimorghAnswerOutcome.partial,
      );
      session = SimorghTeachingEngine.recordDiagnostic(
        session,
        SimorghAnswerOutcome.incorrect,
      );
      session = SimorghTeachingEngine.recordDiagnostic(
        session,
        SimorghAnswerOutcome.correct,
      );
      expect(session.stage, SimorghTeachingStage.explanation);
      expect(session.diagnosticCount, 3);
      expect(session.diagnosticCorrect, 1);

      session = SimorghTeachingEngine.recordExplanationCheck(
        session,
        SimorghAnswerOutcome.incorrect,
      );
      expect(session.stage, SimorghTeachingStage.explanation);
      expect(session.explanationVariant, 1);
      session = SimorghTeachingEngine.recordExplanationCheck(
        session,
        SimorghAnswerOutcome.correct,
      );
      expect(session.stage, SimorghTeachingStage.guidedPractice);

      session = SimorghTeachingEngine.recordPractice(
        session: session,
        outcome: SimorghAnswerOutcome.partial,
        error: SimorghErrorKind.procedural,
      );
      expect(session.stage, SimorghTeachingStage.reteach);
      expect(session.lastError, SimorghErrorKind.procedural);

      session = SimorghTeachingEngine.recordReteachCheck(
        session: session,
        outcome: SimorghAnswerOutcome.incorrect,
        error: SimorghErrorKind.conceptual,
      );
      expect(session.stage, SimorghTeachingStage.reteach);
      session = SimorghTeachingEngine.recordReteachCheck(
        session: session,
        outcome: SimorghAnswerOutcome.correct,
      );
      expect(session.stage, SimorghTeachingStage.guidedPractice);

      session = SimorghTeachingEngine.recordPractice(
        session: session,
        outcome: SimorghAnswerOutcome.correct,
      );
      expect(session.stage, SimorghTeachingStage.masteryCheck);

      session = SimorghTeachingEngine.recordMasteryCheck(
        session: session,
        outcome: SimorghAnswerOutcome.correct,
      );
      session = SimorghTeachingEngine.recordMasteryCheck(
        session: session,
        outcome: SimorghAnswerOutcome.partial,
      );
      session = SimorghTeachingEngine.recordMasteryCheck(
        session: session,
        outcome: SimorghAnswerOutcome.correct,
      );

      expect(session.stage, SimorghTeachingStage.completed);
      expect(session.isComplete, isTrue);
      expect(session.masteryCount, 3);
      expect(session.masteryCorrect, 2);
      expect(session.masteryAccuracy, closeTo(2 / 3, 0.001));
      expect(session.practiceAttempts, 2);
      expect(session.reteachCount, 1);
    });

  });
  test('unclear answers do not count as negative learning evidence', () {
    final diagnostic = SimorghTeachingEngine.start(topic: 'کسرها');
    expect(
      SimorghTeachingEngine.recordDiagnostic(
        diagnostic,
        SimorghAnswerOutcome.unclear,
      ),
      diagnostic,
    );

    final explanation = diagnostic.copyWith(
      stage: SimorghTeachingStage.explanation,
    );
    expect(
      SimorghTeachingEngine.recordExplanationCheck(
        explanation,
        SimorghAnswerOutcome.unclear,
      ),
      explanation,
    );

    final practice = diagnostic.copyWith(
      stage: SimorghTeachingStage.guidedPractice,
    );
    expect(
      SimorghTeachingEngine.recordPractice(
        session: practice,
        outcome: SimorghAnswerOutcome.unclear,
      ),
      practice,
    );

    final reteach = diagnostic.copyWith(
      stage: SimorghTeachingStage.reteach,
    );
    expect(
      SimorghTeachingEngine.recordReteachCheck(
        session: reteach,
        outcome: SimorghAnswerOutcome.unclear,
      ),
      reteach,
    );

    final mastery = diagnostic.copyWith(
      stage: SimorghTeachingStage.masteryCheck,
    );
    expect(
      SimorghTeachingEngine.recordMasteryCheck(
        session: mastery,
        outcome: SimorghAnswerOutcome.unclear,
      ),
      mastery,
    );
  });

}
