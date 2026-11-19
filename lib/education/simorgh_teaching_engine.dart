/// Deterministic teaching-session state machine, independent of any AI provider.
/// The model evaluates answers; this engine controls the learning sequence.
enum SimorghTeachingStage {
  diagnostic,
  explanation,
  guidedPractice,
  reteach,
  masteryCheck,
  completed,
}

enum SimorghAnswerOutcome { correct, partial, incorrect, unclear }

enum SimorghErrorKind {
  conceptual,
  prerequisite,
  procedural,
  calculation,
  careless,
  unknown,
}

class SimorghTeachingSession {
  const SimorghTeachingSession({
    required this.topic,
    required this.grade,
    required this.stage,
    this.diagnosticCount = 0,
    this.diagnosticCorrect = 0,
    this.practiceAttempts = 0,
    this.masteryCount = 0,
    this.masteryCorrect = 0,
    this.reteachCount = 0,
    this.explanationVariant = 0,
    this.lastError,
  });

  final String topic;
  final String grade;
  final SimorghTeachingStage stage;
  final int diagnosticCount;
  final int diagnosticCorrect;
  final int practiceAttempts;
  final int masteryCount;
  final int masteryCorrect;
  final int reteachCount;
  final int explanationVariant;
  final SimorghErrorKind? lastError;

  double get diagnosticAccuracy =>
      diagnosticCount == 0 ? 0 : diagnosticCorrect / diagnosticCount;

  double get masteryAccuracy =>
      masteryCount == 0 ? 0 : masteryCorrect / masteryCount;

  bool get isComplete => stage == SimorghTeachingStage.completed;

  SimorghTeachingSession copyWith({
    SimorghTeachingStage? stage,
    int? diagnosticCount,
    int? diagnosticCorrect,
    int? practiceAttempts,
    int? masteryCount,
    int? masteryCorrect,
    int? reteachCount,
    int? explanationVariant,
    SimorghErrorKind? lastError,
    bool clearLastError = false,
  }) => SimorghTeachingSession(
    topic: topic,
    grade: grade,
    stage: stage ?? this.stage,
    diagnosticCount: diagnosticCount ?? this.diagnosticCount,
    diagnosticCorrect: diagnosticCorrect ?? this.diagnosticCorrect,
    practiceAttempts: practiceAttempts ?? this.practiceAttempts,
    masteryCount: masteryCount ?? this.masteryCount,
    masteryCorrect: masteryCorrect ?? this.masteryCorrect,
    reteachCount: reteachCount ?? this.reteachCount,
    explanationVariant: explanationVariant ?? this.explanationVariant,
    lastError: clearLastError ? null : (lastError ?? this.lastError),
  );
}

class SimorghTeachingEngine {
  const SimorghTeachingEngine._();

  static const diagnosticQuestionLimit = 3;
  static const masteryQuestionLimit = 3;
  static const masteryPassCount = 2;

  static SimorghTeachingSession start({
    required String topic,
    String grade = '',
  }) {
    final cleanTopic = topic.trim();
    if (cleanTopic.isEmpty) {
      throw ArgumentError.value(topic, 'topic', 'موضوع درس نباید خالی باشد.');
    }
    return SimorghTeachingSession(
      topic: cleanTopic,
      grade: grade.trim(),
      stage: SimorghTeachingStage.diagnostic,
    );
  }

  /// Record a model-evaluated answer to one short diagnostic question.
  static SimorghTeachingSession recordDiagnostic(
    SimorghTeachingSession session,
    SimorghAnswerOutcome outcome,
  ) {
    _requireStage(session, SimorghTeachingStage.diagnostic);
    if (outcome == SimorghAnswerOutcome.unclear ||
        session.diagnosticCount >= diagnosticQuestionLimit) return session;
    final count = session.diagnosticCount + 1;
    final correct = session.diagnosticCorrect +
        (outcome == SimorghAnswerOutcome.correct ? 1 : 0);
    final stage = count < diagnosticQuestionLimit
        ? SimorghTeachingStage.diagnostic
        : correct >= 2
            ? SimorghTeachingStage.guidedPractice
            : SimorghTeachingStage.explanation;
    return session.copyWith(
      stage: stage,
      diagnosticCount: count,
      diagnosticCorrect: correct,
    );
  }

  static SimorghTeachingSession beginGuidedPractice(
    SimorghTeachingSession session,
  ) {
    _requireStage(session, SimorghTeachingStage.explanation);
    return session.copyWith(stage: SimorghTeachingStage.guidedPractice);
  }

  /// A correct attempt advances to a transfer/mastery check. A weak attempt
  /// triggers a different explanation, not repetition of the same wording.
  static SimorghTeachingSession recordPractice({
    required SimorghTeachingSession session,
    required SimorghAnswerOutcome outcome,
    SimorghErrorKind error = SimorghErrorKind.unknown,
  }) {
    _requireStage(session, SimorghTeachingStage.guidedPractice);
    if (outcome == SimorghAnswerOutcome.unclear) return session;
    final attempts = session.practiceAttempts + 1;
    if (outcome == SimorghAnswerOutcome.correct) {
      return session.copyWith(
        stage: SimorghTeachingStage.masteryCheck,
        practiceAttempts: attempts,
        clearLastError: true,
        masteryCount: 0,
        masteryCorrect: 0,
      );
    }
    return session.copyWith(
      stage: SimorghTeachingStage.reteach,
      practiceAttempts: attempts,
      reteachCount: session.reteachCount + 1,
      explanationVariant: session.explanationVariant + 1,
      lastError: error,
    );
  }

  static SimorghTeachingSession recordExplanationCheck(
    SimorghTeachingSession session,
    SimorghAnswerOutcome outcome,
  ) {
    _requireStage(session, SimorghTeachingStage.explanation);
    if (outcome == SimorghAnswerOutcome.unclear) return session;
    if (outcome == SimorghAnswerOutcome.correct) {
      return session.copyWith(stage: SimorghTeachingStage.guidedPractice);
    }
    return session.copyWith(
      explanationVariant: session.explanationVariant + 1,
      lastError: SimorghErrorKind.unknown,
    );
  }

  static SimorghTeachingSession recordReteachCheck({
    required SimorghTeachingSession session,
    required SimorghAnswerOutcome outcome,
    SimorghErrorKind error = SimorghErrorKind.unknown,
  }) {
    _requireStage(session, SimorghTeachingStage.reteach);
    if (outcome == SimorghAnswerOutcome.unclear) return session;
    if (outcome == SimorghAnswerOutcome.correct) {
      return session.copyWith(stage: SimorghTeachingStage.guidedPractice, clearLastError: true);
    }
    return session.copyWith(
      explanationVariant: session.explanationVariant + 1,
      lastError: error,
    );
  }

  static SimorghTeachingSession finishReteach(
    SimorghTeachingSession session,
  ) {
    _requireStage(session, SimorghTeachingStage.reteach);
    return session.copyWith(stage: SimorghTeachingStage.guidedPractice);
  }

  static SimorghTeachingSession recordMasteryCheck({
    required SimorghTeachingSession session,
    required SimorghAnswerOutcome outcome,
    SimorghErrorKind error = SimorghErrorKind.unknown,
  }) {
    _requireStage(session, SimorghTeachingStage.masteryCheck);
    if (outcome == SimorghAnswerOutcome.unclear) return session;
    if (session.masteryCount >= masteryQuestionLimit) return session;
    final count = session.masteryCount + 1;
    final correct = session.masteryCorrect +
        (outcome == SimorghAnswerOutcome.correct ? 1 : 0);
    if (count < masteryQuestionLimit) {
      return session.copyWith(masteryCount: count, masteryCorrect: correct);
    }
    if (correct >= masteryPassCount) {
      return session.copyWith(
        stage: SimorghTeachingStage.completed,
        masteryCount: count,
        masteryCorrect: correct,
        clearLastError: true,
      );
    }
    return session.copyWith(
      stage: SimorghTeachingStage.reteach,
      masteryCount: count,
      masteryCorrect: correct,
      reteachCount: session.reteachCount + 1,
      explanationVariant: session.explanationVariant + 1,
      lastError: error,
    );
  }

  /// Stage-specific direction to append to the provider-neutral tutor prompt.
  static String instructionFor(SimorghTeachingSession session) {
    final grade = session.grade.isEmpty
        ? 'پایه تحصیلی مشخص نشده؛ سطح را از پاسخ‌ها بسنج و حدس قطعی نزن.'
        : 'مقطع/پایه تأییدشده: ${session.grade}.';
    final common = 'موضوع: «${session.topic}». $grade '
        'فارسی روان و متناسب با سطح دانش‌آموز به‌کار ببر. هر نوبت فقط یک پرسش '
        'یا یک گام آموزشی ارائه کن. پاسخ را پیش از تلاش دانش‌آموز لو نده، '
        'مگر اینکه صریحاً توضیح کامل بخواهد.';
    switch (session.stage) {
      case SimorghTeachingStage.diagnostic:
        return '$common ابتدا یک پرسش کوتاه و هدفمند برای سنجش پیش‌نیازها '
            'بپرس؛ سؤال‌ها را حداکثر در سه گام و از آسان به متوسط تنظیم کن. '
            'از آزمون طولانی و نمره‌دادن زودهنگام خودداری کن.';
      case SimorghTeachingStage.explanation:
        return '$common ارزیابی اولیه نشان می‌دهد پیش‌نیاز یا فهم پایه نیاز '
            'به تقویت دارد. مفهوم را با زبان ساده، مثال ملموس و یک مثال حل‌شده '
            'توضیح بده؛ سپس یک سؤال فهم‌سنجی بپرس.';
      case SimorghTeachingStage.guidedPractice:
        return '$common با روش سقراطی راهنمایی کن: ابتدا یک سرنخ کوچک بده، '
            'فرصت فکرکردن بده و فقط در صورت نیاز سرنخ بعدی را ارائه کن. '
            'هر بار فقط یک سؤال تمرینی متناسب با سطح بده.';
      case SimorghTeachingStage.reteach:
        final error = session.lastError?.name ?? 'نامشخص';
        return '$common پاسخ قبلی نیازمند بازآموزی بود؛ نوع خطای احتمالی: $error. '
            'همان توضیح را تکرار نکن. از تشبیه، نمودار ذهنی، مثال روزمره یا '
            'روش توضیح متفاوت استفاده کن و سپس یک تمرین ساده‌تر بده. '
            'نسخه توضیح جایگزین: ${session.explanationVariant}.';
      case SimorghTeachingStage.masteryCheck:
        return '$common اکنون انتقال یادگیری را بسنج: مسئله‌ای تازه با همان '
            'مفهوم اما ظاهر متفاوت طرح کن. جواب را مستقیم نده و از دانش‌آموز '
            'بخواه دلیل انتخاب روش را هم کوتاه توضیح دهد.';
      case SimorghTeachingStage.completed:
        return '$common جلسه سنجش به حد پذیرش رسیده است. خلاصه کن چه چیزی '
            'یاد گرفته شد، شواهد موفقیت چه بود و کدام بخش هنوز نیازمند مرور '
            'است. ادعای تسلط قطعی نکن و یک تمرین مرور آینده پیشنهاد بده.';
    }
  }

  static void _requireStage(
    SimorghTeachingSession session,
    SimorghTeachingStage expected,
  ) {
    if (session.stage != expected) {
      throw StateError('مرحله فعلی جلسه با عملیات درخواستی سازگار نیست.');
    }
  }
}
