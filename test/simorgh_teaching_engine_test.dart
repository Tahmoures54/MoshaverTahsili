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
  });
}
