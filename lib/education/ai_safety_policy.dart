/// Offline safety preflight for explicit self-harm signals.
///
/// IMPORTANT:
/// - This is a conservative keyword/rule-based screen.
/// - It is NOT a clinical risk assessment.
/// - It cannot reliably detect every crisis, euphemism, indirect expression,
///   language, spelling variation or deliberate obfuscation.
/// - Educational discussion, quotations, historical accounts and negated
///   statements may produce positive results.
/// - A positive result must prevent remote AI submission.
/// - A negative result does NOT prove that a user is safe.
///
/// Keep this policy independent from remote AI services, wallet state,
/// API credentials and network availability.
///
/// The application is responsible for:
/// - Enforcing the remote-request block.
/// - Displaying the local response.
/// - Passing the relevant user history without silently removing safety
///   signals before assessment.
/// - Providing human-support and emergency-help entry points.

enum AiSafetyDisposition { allow, urgentHumanSupport }

class AiSafetyResult {
  const AiSafetyResult(this.disposition, {this.localResponse});

  final AiSafetyDisposition disposition;
  final String? localResponse;

  bool get shouldBlockRemoteAi => disposition != AiSafetyDisposition.allow;

  bool get requiresHumanSupport =>
      disposition == AiSafetyDisposition.urgentHumanSupport;
}

class AiSafetyPolicy {
  AiSafetyPolicy._();

  /// Maximum normalized character distance between an intent expression
  /// and a related action.
  ///
  /// This is a matching heuristic, not a clinical threshold.
  static const int _maxIntentDistance = 80;

  /// Inspect all supplied prior user messages by default.
  ///
  /// Values used by assessTurn / assessRemoteHistory:
  /// - -1: inspect all supplied user messages.
  /// -  0: inspect no prior user messages.
  /// - >0: inspect at most this many recent non-empty user messages.
  ///
  /// A positive limit intentionally narrows coverage. Do not use a limited
  /// scan as the only safeguard for a larger outgoing history.
  static const int defaultMaxPriorUserMessages = -1;

  static const AiSafetyResult _allowResult = AiSafetyResult(
    AiSafetyDisposition.allow,
  );

  /// Locally displayed support response.
  ///
  /// Do not assume the user's country from their language.
  /// Emergency numbers should be supplied by a separate, verified,
  /// location-aware application feature.
  static const String _urgentResponse =
      'پیام تو به سرویس هوش مصنوعی ارسال نشد. '
      'ممنونم که این موضوع را مطرح کردی. '
      'اگر این موضوع درباره خودت یا کسی نزدیک توست، '
      'لازم نیست با این وضعیت تنها بمانی.\n\n'
      'اگر احساس می‌کنی ممکن است همین حالا به خودت آسیب بزنی، '
      'لطفاً تنها نمان، از داروها و وسایل خطرناک فاصله بگیر '
      'و فوراً به یک فرد امن و قابل اعتماد که نزدیکت است اطلاع بده.\n\n'
      'اگر همین حالا به خودت آسیب زده‌ای یا چیزی مصرف کرده‌ای '
      'که ممکن است خطرناک باشد، فوراً از خدمات اضطراری '
      'محل زندگی‌ات کمک بگیر؛ منتظر پاسخ برنامه نمان.\n\n'
      'اگر خطر فوری وجود ندارد، باز هم مهم است که امروز '
      'با والد یا سرپرست امن، مشاور مدرسه، '
      'یک بزرگسال قابل اعتماد یا متخصص سلامت روان صحبت کنی. '
      'اگر یکی از نزدیکانت برایت امن نیست، فرد دیگری را انتخاب کن.\n\n'
      'برای شروع می‌توانی بگویی: '
      '«حالم خوب نیست و لازم دارم کنارم بمانی '
      'و کمکم کنی با یک متخصص صحبت کنم.»\n\n'
      'تو شایسته دریافت کمک و حمایت انسانی هستی. '
      'این برنامه جایگزین کمک تخصصی یا خدمات اورژانسی نیست.';

  static const AiSafetyResult _urgentResult = AiSafetyResult(
    AiSafetyDisposition.urgentHumanSupport,
    localResponse: _urgentResponse,
  );

  // ---------------------------------------------------------------------------
  // 1. Reusable normalization patterns
  // ---------------------------------------------------------------------------

  static final RegExp _arabicDiacritics = RegExp(
    r'[\u0610-\u061A\u064B-\u065F\u0670\u06D6-\u06ED]',
  );

  /// Formatting-only marks are removed rather than treated as word breaks.
  static final RegExp _directionAndFormattingMarks = RegExp(
    r'[\u061C\u200E\u200F\u202A-\u202E\u2060-\u206F\uFEFF]',
  );

  /// Zero-width separators become spaces so ordinary Persian half-space
  /// forms match patterns such as "می\s*خواهم".
  static final RegExp _zeroWidthSeparators = RegExp(r'[\u200B-\u200D]');

  static final RegExp _digits = RegExp(r'[۰-۹٠-٩]');

  static final RegExp _punctuation = RegExp(
    r'''[،؛؟!.,:;?…«»"“”()\[\]{}<>/\\|_ـ\-–—]+''',
  );

  static final RegExp _whitespace = RegExp(r'\s+');

  // ---------------------------------------------------------------------------
  // 2. Persian intent + action expressions
  // ---------------------------------------------------------------------------

  static const String _persianIntentPattern =
      r'(?:'
      r'می\s*(?:خوام|خواهم|خواستم)|'
      r'قصد\s*دارم|'
      r'تصمیم\s*(?:دارم|گرفتم)|'
      r'برنامه\s*دارم|'
      r'فکر\s*می\s*کنم|'
      r'به\s*این\s*فکر\s*می\s*کنم|'
      r'دارم\s*فکر\s*می\s*کنم|'
      r'دلم\s*می\s*(?:خواد|خواهد)|'
      r'کاش'
      r')';

  static const String _persianActionPattern =
      r'(?:'
      r'خود\s*کشی|'
      r'خود\s*زنی|'
      r'خودم\s*(?:را|رو)\s*بکشم|'
      r'خودمو\s*بکشم|'
      r'به\s*خودم\s*(?:آسیب|اسیب|صدمه)\s*'
      r'(?:بزنم|وارد\s*کنم)|'
      r'به\s*زندگی(?:\s*(?:ام|م))?\s*پایان\s*'
      r'(?:بدم|بدهم)|'
      r'به\s*زندگیم\s*پایان\s*(?:بدم|بدهم)|'
      r'زندگی(?:\s*(?:ام|م))?\s*(?:را|رو)\s*'
      r'(?:تمام|تموم)\s*کنم|'
      r'زندگیم\s*(?:را|رو)\s*(?:تمام|تموم)\s*کنم|'
      r'بمیرم'
      r')';

  static final RegExp _persianIntentAndAction = RegExp(
    '$_persianIntentPattern'
    '.{0,$_maxIntentDistance}'
    '$_persianActionPattern',
    caseSensitive: false,
  );

  // ---------------------------------------------------------------------------
  // 3. Direct Persian signals
  // ---------------------------------------------------------------------------

  static final RegExp _directPersianSignals = RegExp(
    r'(?:'
    // Explicit first-person suicide statements.
    r'خود\s*کشی\s*(?:کنم|کردم|می\s*کنم|خواهم\s*کرد)|'
    r'اقدام\s*به\s*خود\s*کشی|'
    r'خودم\s*(?:را|رو)\s*بکشم|'
    r'خودمو\s*بکشم|'
    // Explicit first-person self-injury statements.
    r'به\s*خودم\s*(?:آسیب|اسیب|صدمه)\s*'
    r'(?:بزنم|می\s*زنم|زدم|وارد\s*(?:کنم|می\s*کنم|کردم))|'
    r'خود\s*زنی\s*(?:کنم|می\s*کنم|کردم)|'
    r'خودم\s*(?:را|رو)\s*'
    r'(?:زخمی\s*(?:کنم|کردم|می\s*کنم)|'
    r'آزار\s*(?:بدهم|بدم|می\s*دهم|می\s*دم))|'
    // Explicit wishes not to remain alive.
    r'(?:دیگه\s*|دیگر\s*)?'
    r'نمی\s*(?:خوام|خواهم)\s*زنده\s*باشم|'
    r'نمی\s*خوام\s*زنده\s*بمونم|'
    r'نمی\s*خواهم\s*زنده\s*بمانم|'
    r'(?:دیگه\s*|دیگر\s*)?'
    r'نمی\s*(?:خوام|خواهم)\s*زندگی\s*کنم|'
    r'کاش\s*مرده\s*بودم|'
    r'کاش\s*می\s*مردم|'
    r'کاش\s*(?:دیگه\s*|دیگر\s*)?زنده\s*نبودم|'
    r'کاش\s*زنده\s*نباشم|'
    // Explicit suicide thoughts.
    r'فکر\s*خود\s*کشی\s*(?:دارم|می\s*کنم)|'
    r'افکار\s*خود\s*کشی\s*دارم|'
    r'به\s*خود\s*کشی\s*فکر\s*می\s*کنم|'
    r'دارم\s*به\s*خود\s*کشی\s*فکر\s*می\s*کنم|'
    // Difficulty stopping self-injury.
    r'نمی\s*(?:توانم|تونم)'
    r'\s*جلوی\s*(?:خودم|خود\s*زنی)'
    r'\s*(?:را|رو)?\s*بگیرم'
    r')',
    caseSensitive: false,
  );

  // ---------------------------------------------------------------------------
  // 4. English signals
  // ---------------------------------------------------------------------------

  /// Deliberately conservative.
  ///
  /// Generic terms such as "suicidal" and "self harm" also match.
  /// This can block educational, quoted or negated statements.
  ///
  /// Do not add a blanket exemption for "not", "don't" or Persian "نمی":
  /// negation alone does not establish safety.
  static final RegExp _englishSignals = RegExp(
    r'(?:^|[^a-z])'
    r'(?:'
    r'i\s+(?:want|wanna)\s+(?:to\s+)?die|'
    r'i\s+wish\s+i\s+(?:was|were)\s+dead|'
    r'i\s+wish\s+i\s+'
    r'(?:was\s+not|were\s+not|wasn\x27t|weren\x27t)'
    r'\s+alive|'
    r'i\s+(?:do\s+not|don\x27t)\s+want\s+to\s+'
    r'(?:live|be\s+alive|keep\s+living)|'
    r'i\s+(?:want|plan|intend|am\s+planning)\s+to\s+'
    r'(?:kill|hurt|harm)\s+myself|'
    r'i\s+(?:am|m)\s+going\s+to\s+kill\s+myself|'
    r'i\x27m\s+going\s+to\s+kill\s+myself|'
    r'i\s+will\s+kill\s+myself|'
    r'i\x27ll\s+kill\s+myself|'
    r'i\s+intend\s+to\s+die|'
    r'kill\s+myself|'
    r'killing\s+myself|'
    r'end\s+my\s+life|'
    r'ending\s+my\s+life|'
    r'take\s+my\s+own\s+life|'
    r'hurt\s+myself|'
    r'hurting\s+myself|'
    r'harm\s+myself|'
    r'harming\s+myself|'
    r'self\s*harm(?:ing)?|'
    r'suicidal|'
    r'suicide\s+'
    r'(?:attempt|plan|thoughts|ideation)|'
    r'attempted\s+suicide'
    r')'
    r'(?:$|[^a-z])',
    caseSensitive: false,
  );

  // ---------------------------------------------------------------------------
  // 5. Normalization
  // ---------------------------------------------------------------------------

  /// Normalize common Persian/Arabic variations and formatting differences.
  ///
  /// This is not general Unicode normalization and does not defeat every
  /// possible spelling variation or obfuscation.
  static String normalize(String message) {
    var result = message
        // Arabic characters -> Persian equivalents.
        .replaceAll('ي', 'ی')
        .replaceAll('ى', 'ی')
        .replaceAll('ك', 'ک')
        // Common apostrophe variants -> ASCII apostrophe.
        .replaceAll('’', "'")
        .replaceAll('‘', "'")
        .replaceAll('ʼ', "'")
        .replaceAll('＇', "'")
        // Remove tatweel and combining marks.
        .replaceAll('ـ', '')
        .replaceAll(_arabicDiacritics, '')
        // Formatting marks do not carry lexical meaning.
        .replaceAll(_directionAndFormattingMarks, '')
        // Preserve ordinary word boundaries around half-spaces.
        .replaceAll(_zeroWidthSeparators, ' ')
        // Normalize Persian and Arabic digits.
        .replaceAllMapped(_digits, (match) {
          final code = match.group(0)!.codeUnitAt(0);

          if (code >= 0x06F0 && code <= 0x06F9) {
            return String.fromCharCode(code - 0x06F0 + 0x30);
          }

          if (code >= 0x0660 && code <= 0x0669) {
            return String.fromCharCode(code - 0x0660 + 0x30);
          }

          return match.group(0)!;
        })
        // Preserve apostrophes for English contractions.
        .replaceAll(_punctuation, ' ')
        .replaceAll(_whitespace, ' ')
        .trim()
        .toLowerCase();

    return result;
  }

  // ---------------------------------------------------------------------------
  // 6. Single-message assessment
  // ---------------------------------------------------------------------------

  static AiSafetyResult assess(String message) {
    if (message.trim().isEmpty) {
      return _allowResult;
    }

    final normalized = normalize(message);

    if (normalized.isEmpty) {
      return _allowResult;
    }

    if (_persianIntentAndAction.hasMatch(normalized) ||
        _directPersianSignals.hasMatch(normalized) ||
        _englishSignals.hasMatch(normalized)) {
      return _urgentResult;
    }

    return _allowResult;
  }

  // ---------------------------------------------------------------------------
  // 7. History assessment
  // ---------------------------------------------------------------------------

  /// Assess user content in a history that may be submitted remotely.
  ///
  /// History is expected in chronological order:
  /// oldest message first, newest message last.
  ///
  /// IMPORTANT:
  /// - Only user messages are inspected.
  /// - Failed, pending and cancelled user records are still inspected.
  ///   Transport/storage status does not invalidate the user's words.
  /// - Assistant messages are not used to infer the user's condition.
  /// - By default, every supplied non-empty user message is inspected.
  /// - This method does not change or sanitize the supplied history.
  ///
  /// A negative result is not permission to ignore other privacy or
  /// application-level restrictions.
  static AiSafetyResult assessRemoteHistory(
    List<Map<String, dynamic>> history, {
    int maxPriorUserMessages = defaultMaxPriorUserMessages,
  }) {
    _validateHistoryLimit(maxPriorUserMessages);

    if (history.isEmpty || maxPriorUserMessages == 0) {
      return _allowResult;
    }

    var inspected = 0;

    for (final message in history.reversed) {
      if (maxPriorUserMessages > 0 && inspected >= maxPriorUserMessages) {
        break;
      }

      final content = _userContent(message);

      if (content == null) {
        continue;
      }

      inspected++;

      final result = assess(content);

      if (result.shouldBlockRemoteAi) {
        return result;
      }
    }

    return _allowResult;
  }

  /// Assess the current message first, then the supplied user history.
  ///
  /// The default is a full scan of the supplied history.
  /// This avoids automatically clearing a previous signal after a few
  /// short follow-up messages while that signal remains in the history.
  ///
  /// This is not a permanent crisis-state latch:
  /// if the caller removes a message from history, this stateless policy
  /// cannot remember it.
  ///
  /// This method does not reliably detect intent split across multiple
  /// messages that individually contain no recognized signal.
  static AiSafetyResult assessTurn(
    String currentMessage,
    List<Map<String, dynamic>> history, {
    int maxPriorUserMessages = defaultMaxPriorUserMessages,
  }) {
    _validateHistoryLimit(maxPriorUserMessages);

    final current = assess(currentMessage);

    if (current.shouldBlockRemoteAi) {
      return current;
    }

    return assessRemoteHistory(
      history,
      maxPriorUserMessages: maxPriorUserMessages,
    );
  }

  static String? _userContent(Map<String, dynamic> message) {
    final role = message['role'];

    if (role is! String || role.trim().toLowerCase() != 'user') {
      return null;
    }

    final content = message['content'];

    if (content is! String || content.trim().isEmpty) {
      return null;
    }

    // Do not inspect status here.
    //
    // A failed or pending request can still contain an explicit safety
    // signal and must not be treated as harmless for that reason.
    return content;
  }

  static void _validateHistoryLimit(int value) {
    if (value < -1) {
      throw ArgumentError.value(
        value,
        'maxPriorUserMessages',
        'Use -1 for all messages, 0 for none, or a positive limit.',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 8. Application integration helpers
  // ---------------------------------------------------------------------------

  /// Check one message without conversation history.
  static bool mustBlockRemoteAi(String message) {
    return assess(message).shouldBlockRemoteAi;
  }

  /// Check the current message and supplied user history.
  static bool mustBlockRemoteAiTurn(
    String currentMessage,
    List<Map<String, dynamic>> history, {
    int maxPriorUserMessages = defaultMaxPriorUserMessages,
  }) {
    return assessTurn(
      currentMessage,
      history,
      maxPriorUserMessages: maxPriorUserMessages,
    ).shouldBlockRemoteAi;
  }

  /// Return the local support response for a single message.
  static String? getUrgentLocalResponse(String message) {
    return assess(message).localResponse;
  }

  /// Return the local support response considering user history.
  static String? getUrgentLocalResponseForTurn(
    String currentMessage,
    List<Map<String, dynamic>> history, {
    int maxPriorUserMessages = defaultMaxPriorUserMessages,
  }) {
    return assessTurn(
      currentMessage,
      history,
      maxPriorUserMessages: maxPriorUserMessages,
    ).localResponse;
  }
}
