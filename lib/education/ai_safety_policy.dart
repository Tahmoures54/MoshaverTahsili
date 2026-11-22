
/// Offline safety preflight for explicit self-harm signals.
///
/// IMPORTANT:
/// - This is a conservative keyword/rule-based screen.
/// - It is NOT a clinical risk assessment.
/// - It cannot reliably detect every crisis, euphemism, or indirect expression.
/// - A positive result must prevent remote AI submission.
/// - A negative result does NOT prove that a user is safe.
///
/// Keep this policy independent from remote AI services.

enum AiSafetyDisposition {
  allow,
  urgentHumanSupport,
}

class AiSafetyResult {
  const AiSafetyResult(
    this.disposition, {
    this.localResponse,
  });

  final AiSafetyDisposition disposition;
  final String? localResponse;

  bool get shouldBlockRemoteAi =>
      disposition != AiSafetyDisposition.allow;

  bool get requiresHumanSupport =>
      disposition == AiSafetyDisposition.urgentHumanSupport;
}

class AiSafetyPolicy {
  AiSafetyPolicy._();

  /// Maximum distance between an expression of intent and an action.
  static const int _maxIntentDistance = 80;

  /// Maximum number of previous successful user messages to inspect.
  static const int defaultMaxPriorUserMessages = 3;

  /// Local response shown when a safety signal is detected.
  ///
  /// This response must be displayed locally.
  /// The application must enforce the remote-request block separately.
  static const String _urgentResponse =
      'ممنونم که درباره این موضوع با من صحبت کردی. '
      'خوشحالم که احساست را پنهان نکردی.\n\n'
      'لازم نیست در این شرایط تنها بمانی. '
      'اگر احساس می‌کنی ممکن است همین حالا به خودت آسیب بزنی، '
      'لطفاً تنها نمان، از داروها و وسایل خطرناک فاصله بگیر '
      'و فوراً به یک فرد قابل اعتماد که نزدیکت است اطلاع بده.\n\n'
      'اگر خطر فوری وجود دارد، از خدمات اورژانسی محل زندگی‌ات '
      'کمک بگیر.\n\n'
      'اگر در معرض خطر فوری نیستی، باز هم مهم است که امروز '
      'با والد یا سرپرست امن، مشاور مدرسه یا متخصص سلامت روان '
      'صحبت کنی.\n\n'
      'اگر صحبت با یکی از نزدیکانت برایت دشوار است، '
      'می‌توانی از مشاور مدرسه یا یک بزرگسال قابل اعتماد دیگر '
      'کمک بخواهی.\n\n'
      'تو ارزشمند هستی و شایسته دریافت کمک و حمایت انسانی هستی. '
      'من جایگزین کمک تخصصی و انسانی نیستم.';

  static const AiSafetyResult _urgentResult = AiSafetyResult(
    AiSafetyDisposition.urgentHumanSupport,
    localResponse: _urgentResponse,
  );

  // ---------------------------------------------------------------------------
  // 1. Persian intent + action expressions
  // ---------------------------------------------------------------------------

  static final RegExp _persianIntentAndAction = RegExp(
    r'(?:'
    r'می\s*خوام|'
    r'می\s*خواهم|'
    r'قصد\s*دارم|'
    r'تصمیم\s*دارم|'
    r'برنامه\s*دارم|'
    r'فکر\s*می\s*کنم|'
    r'به\s*این\s*فکر\s*می\s*کنم|'
    r'دلم\s*می\s*خواد|'
    r'دلم\s*می\s*خواهد|'
    r'کاش'
    r')'
    '.{0,$_maxIntentDistance}'
    r'(?:'
    r'خودکشی|'
    r'خودم\s*را\s*بکشم|'
    r'خودمو\s*بکشم|'
    r'به\s*خودم\s*(?:آسیب|صدمه)\s*(?:بزنم|بزنم|وارد\s*کنم)|'
    r'به\s*زندگی(?:\s*(?:ام|م))?\s*پایان\s*بدم|'
    r'به\s*زندگی(?:\s*(?:ام|م))?\s*پایان\s*بدهم|'
    r'بمیرم|'
    r'به\s*خودم\s*صدمه'
    r')',
    caseSensitive: false,
  );

  // ---------------------------------------------------------------------------
  // 2. Direct Persian self-harm expressions
  // ---------------------------------------------------------------------------

  static final RegExp _directPersianSignals = RegExp(
    r'(?:'
    r'خودکشی\s*(?:کنم|کردم|می\s*کنم|خواهم\s*کرد)|'
    r'اقدام\s*به\s*خودکشی|'
    r'خودم\s*را\s*بکشم|'
    r'خودمو\s*بکشم|'
    r'به\s*خودم\s*(?:آسیب|صدمه)\s*(?:بزنم|می\s*زنم|زدم)|'
    r'به\s*خودم\s*(?:آسیب|صدمه)\s*وارد\s*کنم|'
    r'خودزنی\s*(?:کنم|می\s*کنم|کردم)|'
    r'دیگه\s*نمی\s*خوام\s*زنده\s*باشم|'
    r'دیگر\s*نمی\s*خواهم\s*زنده\s*باشم|'
    r'نمی\s*خوام\s*زنده\s*بمونم|'
    r'نمی\s*خواهم\s*زنده\s*بمانم|'
    r'کاش\s*مرده\s*بودم|'
    r'کاش\s*می\s*مردم|'
    r'کاش\s*دیگه\s*زنده\s*نبودم|'
    r'فکر\s*خودکشی\s*(?:دارم|می\s*کنم)|'
    r'به\s*خودکشی\s*فکر\s*می\s*کنم'
    r')',
    caseSensitive: false,
  );

  // ---------------------------------------------------------------------------
  // 3. English self-harm expressions
  // ---------------------------------------------------------------------------

  static final RegExp _englishSignals = RegExp(
    r'(?:^|[^a-z])'
    r'(?:'
    r'i\s+want\s+to\s+die|'
    r'i\s+want\s+to\s+kill\s+myself|'
    r'i\s+am\s+going\s+to\s+kill\s+myself|'
    r'i\s+will\s+kill\s+myself|'
    r'i\s+plan\s+to\s+kill\s+myself|'
    r'i\s+plan\s+to\s+end\s+my\s+life|'
    r'i\s+intend\s+to\s+die|'
    r'i\s+intend\s+to\s+hurt\s+myself|'
    r'i\s+want\s+to\s+hurt\s+myself|'
    r'kill\s+myself|'
    r'end\s+my\s+life|'
    r'hurt\s+myself|'
    r'self[- ]harm|'
    r'suicidal'
    r')'
    r'(?:$|[^a-z])',
    caseSensitive: false,
  );

  // ---------------------------------------------------------------------------
  // 4. Normalization
  // ---------------------------------------------------------------------------

  static String normalize(String message) {
    var result = message
        // Arabic characters -> Persian equivalents.
        .replaceAll('ي', 'ی')
        .replaceAll('ى', 'ی')
        .replaceAll('ك', 'ک')

        // Remove Arabic tatweel.
        .replaceAll('ـ', '')

        // Remove Arabic diacritics.
        .replaceAll(
          RegExp(r'[\u064B-\u065F\u0670]'),
          '',
        )

        // Normalize invisible direction and zero-width characters.
        .replaceAll(
          RegExp(r'[\u200B-\u200F\u202A-\u202E\u2060\uFEFF]'),
          ' ',
        )

        // Normalize Arabic and Persian digits to English digits.
        .replaceAllMapped(
          RegExp(r'[۰-۹٠-٩]'),
          (match) {
            final character = match.group(0)!;
            final code = character.codeUnitAt(0);

            if (code >= 0x06F0 && code <= 0x06F9) {
              return String.fromCharCode(
                code - 0x06F0 + 0x30,
              );
            }

            if (code >= 0x0660 && code <= 0x0669) {
              return String.fromCharCode(
                code - 0x0660 + 0x30,
              );
            }

            return character;
          },
        );

    // Convert punctuation and line breaks to spaces.
    result = result
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();

    return result;
  }

  // ---------------------------------------------------------------------------
  // 5. Core assessment
  // ---------------------------------------------------------------------------

  static AiSafetyResult assess(String message) {
    if (message.trim().isEmpty) {
      return const AiSafetyResult(
        AiSafetyDisposition.allow,
      );
    }

    final normalized = normalize(message);

    if (normalized.isEmpty) {
      return const AiSafetyResult(
        AiSafetyDisposition.allow,
      );
    }

    final hasPersianIntent =
        _persianIntentAndAction.hasMatch(normalized);

    final hasDirectPersianSignal =
        _directPersianSignals.hasMatch(normalized);

    final hasEnglishSignal =
        _englishSignals.hasMatch(normalized);

    if (hasPersianIntent ||
        hasDirectPersianSignal ||
        hasEnglishSignal) {
      return _urgentResult;
    }

    return const AiSafetyResult(
      AiSafetyDisposition.allow,
    );
  }

  // ---------------------------------------------------------------------------
  // 6. Assessment with recent conversation history
  // ---------------------------------------------------------------------------

  /// Checks the current message first, then a limited number of recent
  /// successful user messages.
  ///
  /// History is expected to be ordered chronologically:
  /// oldest message first, newest message last.
  ///
  /// Failed and pending messages are ignored.
  ///
  /// Only user messages are inspected.
  ///
  /// A positive signal in recent history is carried forward so that a
  /// subsequent short message does not automatically clear the safety block.
  static AiSafetyResult assessTurn(
    String currentMessage,
    List<Map<String, dynamic>> history, {
    int maxPriorUserMessages = defaultMaxPriorUserMessages,
  }) {
    // Current message always has priority.
    final current = assess(currentMessage);

    if (current.shouldBlockRemoteAi) {
      return current;
    }

    if (maxPriorUserMessages <= 0 || history.isEmpty) {
      return current;
    }

    var inspected = 0;

    // Recent messages first.
    for (final message in history.reversed) {
      if (inspected >= maxPriorUserMessages) {
        break;
      }

      final role = message['role'];

      if (role is! String || role.toLowerCase() != 'user') {
        continue;
      }

      final content = message['content'];

      if (content is! String || content.trim().isEmpty) {
        continue;
      }

      final status = message['status'];

      // Ignore incomplete or failed records.
      if (status is String) {
        final normalizedStatus = status.toLowerCase();

        if (normalizedStatus == 'failed' ||
            normalizedStatus == 'pending') {
          continue;
        }
      }

      inspected++;

      final previous = assess(content);

      if (previous.shouldBlockRemoteAi) {
        return previous;
      }
    }

    return current;
  }

  // ---------------------------------------------------------------------------
  // 7. Explicit helpers for application integration
  // ---------------------------------------------------------------------------

  /// Convenience method for checking whether a message must not be
  /// submitted to a remote AI service.
  static bool mustBlockRemoteAi(String message) {
    return assess(message).shouldBlockRemoteAi;
  }

  /// Returns the local crisis-support response, if one is required.
  static String? getUrgentLocalResponse(String message) {
    return assess(message).localResponse;
  }
}
