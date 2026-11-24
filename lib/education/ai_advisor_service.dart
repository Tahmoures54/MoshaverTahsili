import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'ai_safety_policy.dart';
import 'education_store.dart';
import 'simorgh_persona.dart';

enum AiErrorKind {
  configuration,
  input,
  credits,
  busy,
  network,
  timeout,
  rateLimit,
  server,
  response,
  storage,
  cancelled,
}

/// Only fixed, non-sensitive messages are exposed.
///
/// Never include provider response bodies, headers, credentials,
/// purchase tokens or raw transport exceptions.
class AiException implements Exception {
  const AiException(this.kind, this.message);

  final AiErrorKind kind;
  final String message;

  @override
  String toString() => message;
}

class _InFlightRequest {
  const _InFlightRequest({
    required this.signature,
    required this.future,
    required this.abort,
  });

  // Kept only in memory for the lifetime of the request.
  // Includes the effective request context, not just the question.
  final String signature;
  final Future<String> future;
  final Completer<void> abort;
}

class AiAdvisorService {
  AiAdvisorService({
    http.Client? client,
    String? apiKey,
    String? endpoint,
    String? model,
    this.store,
    this.timeout = const Duration(seconds: 45),
    this.temperature = 0.55,
    this.maxTokens = 1200,
    this.maxConcurrentRequests = 1,
    this.disableDeepSeekThinking = false,
  }) : _ownsClient = client == null,
       client = client ?? http.Client(),
       apiKey = (apiKey ?? const String.fromEnvironment('AI_API_KEY')).trim(),
       endpoint =
           (endpoint ??
                   const String.fromEnvironment(
                     'AI_API_ENDPOINT',
                     defaultValue: 'https://api.avalai.ir/v1',
                   ))
               .trim(),
       model =
           (model ??
                   const String.fromEnvironment(
                     'AI_MODEL',
                     defaultValue: 'deepseek-chat',
                   ))
               .trim();

  final EducationStore? store;

  final bool _ownsClient;
  final http.Client client;

  final String apiKey;
  final String endpoint;
  final String model;

  final Duration timeout;
  final double temperature;
  final int maxTokens;

  /// Applies within this service instance.
  ///
  /// Cross-instance concurrency and ledger locking must be enforced
  /// by EducationStore.
  final int maxConcurrentRequests;

  /// Enable only when the selected provider explicitly supports it.
  final bool disableDeepSeekThinking;

  static const maxRequestBytes = 96 * 1024;
  static const maxResponseBytes = 512 * 1024;

  static const _maxHistoryChars = 18000;
  static const _maxHistoryMessages = 24;
  static const _maxSystemInstructionChars = 12000;
  static const _maxRequestIdChars = 200;

  static int _requestSequence = 0;

  final Map<String, _InFlightRequest> _inFlight = {};

  Uri? _cachedEndpoint;
  bool? _cachedConfigured;

  bool _disposed = false;

  bool get isRunning => _inFlight.isNotEmpty;

  int get activeRequestCount => _inFlight.length;

  bool get isConfigured {
    if (_disposed) return false;

    final cached = _cachedConfigured;
    if (cached != null) return cached;

    try {
      _validateConfiguration();
      return _cachedConfigured = true;
    } on Object {
      return _cachedConfigured = false;
    }
  }

  void _validateConfiguration() {
    if (apiKey.isEmpty ||
        apiKey.contains('\r') ||
        apiKey.contains('\n') ||
        model.isEmpty ||
        model.length > 200 ||
        timeout <= Duration.zero ||
        !temperature.isFinite ||
        temperature < 0 ||
        temperature > 2 ||
        maxTokens <= 0 ||
        maxConcurrentRequests <= 0) {
      throw const AiException(
        AiErrorKind.configuration,
        'تنظیمات سرویس مشاور در این نسخه معتبر نیست.',
      );
    }

    _endpoint();
  }

  Uri _endpoint() {
    final cached = _cachedEndpoint;
    if (cached != null) return cached;

    final uri = Uri.tryParse(endpoint);

    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const AiException(
        AiErrorKind.configuration,
        'نشانی سرویس پاسخ‌گویی در این نسخه معتبر نیست.',
      );
    }

    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');

    return _cachedEndpoint = uri.replace(
      path: path.endsWith('/chat/completions')
          ? path
          : '$path/chat/completions',
    );
  }

  static String _newRequestId() {
    _requestSequence++;

    return 'ai-${DateTime.now().microsecondsSinceEpoch}'
        '-$_requestSequence';
  }

  /// Same-ID concurrent callers share a Future only when their effective
  /// request context is identical.
  ///
  /// Durable idempotency after completion is owned by EducationStore.
  Future<String> ask({
    required Map<String, dynamic>? profile,
    required List<Map<String, dynamic>> history,
    required String question,
    String? requestId,
    String? systemInstruction,
    bool jsonMode = false,
  }) {
    try {
      if (_disposed) {
        throw const AiException(
          AiErrorKind.configuration,
          'سرویس مشاور بسته شده است.',
        );
      }

      final normalizedQuestion = question.trim();
      final id = requestId ?? _newRequestId();

      if (id.trim().isEmpty ||
          id.length > _maxRequestIdChars ||
          RegExp(r'[\u0000-\u001F\u007F]').hasMatch(id)) {
        throw const AiException(AiErrorKind.input, 'شناسه درخواست معتبر نیست.');
      }

      if (normalizedQuestion.isEmpty ||
          normalizedQuestion.length > EducationStore.maxQuestionLength) {
        throw AiException(
          AiErrorKind.input,
          'پرسش باید بین ۱ تا '
          '${EducationStore.maxQuestionLength} نویسه باشد.',
        );
      }

      if (systemInstruction != null &&
          systemInstruction.length > _maxSystemInstructionChars) {
        throw const AiException(
          AiErrorKind.input,
          'دستور آموزشی بیش از حد طولانی است.',
        );
      }

      // Snapshot caller-owned data before the first asynchronous step.
      final profileSnapshot = profile == null
          ? null
          : Map<String, dynamic>.from(profile);

      final historySnapshot = history
          .map((message) => Map<String, dynamic>.from(message))
          .toList();

      // Local safety handling precedes key validation, wallet reservation
      // and any network transmission.
      final safety = AiSafetyPolicy.assessTurn(
        normalizedQuestion,
        historySnapshot,
      );

      final localResponse = safety.shouldBlockRemoteAi
          ? safety.localResponse
          : null;

      if (safety.shouldBlockRemoteAi &&
          (localResponse == null || localResponse.trim().isEmpty)) {
        throw const AiException(
          AiErrorKind.response,
          'پاسخ حمایتی محلی آماده نشد. '
          'از یک بزرگسال مورد اعتماد کمک بگیر.',
        );
      }

      final messages = localResponse == null
          ? _messages(
              profileSnapshot,
              historySnapshot,
              normalizedQuestion,
              systemInstruction: systemInstruction,
            )
          : <Map<String, String>>[];

      final signature = jsonEncode({
        'question': normalizedQuestion,
        'messages': messages,
        'jsonMode': jsonMode,
        'localResponse': localResponse,
      });

      final active = _inFlight[id];

      if (active != null) {
        if (active.signature != signature) {
          throw const AiException(
            AiErrorKind.input,
            'این شناسه هم‌زمان با متن یا زمینه متفاوت '
            'در حال استفاده است.',
          );
        }

        return active.future;
      }

      // A local safety response is free and never enters the remote queue.
      if (localResponse != null) {
        return Future<String>.value(localResponse);
      }

      if (maxConcurrentRequests <= 0) {
        throw const AiException(
          AiErrorKind.configuration,
          'تنظیمات تعداد درخواست‌های مشاور معتبر نیست.',
        );
      }

      if (_inFlight.length >= maxConcurrentRequests) {
        throw const AiException(
          AiErrorKind.busy,
          'یک درخواست مشاور در حال اجراست. '
          'پس از پایان آن دوباره تلاش کن.',
        );
      }

      final abort = Completer<void>();

      // Schedule execution after registering the request.
      // This avoids re-entrant callers missing the in-flight entry.
      final work = Future<String>.microtask(
        () => _execute(
          messages: messages,
          question: normalizedQuestion,
          id: id,
          abort: abort,
          jsonMode: jsonMode,
        ),
      );

      final tracked = work.whenComplete(() {
        final current = _inFlight[id];

        if (identical(current?.abort, abort)) {
          _inFlight.remove(id);
        }
      });

      _inFlight[id] = _InFlightRequest(
        signature: signature,
        future: tracked,
        abort: abort,
      );

      return tracked;
    } on AiException catch (error) {
      return Future<String>.error(error);
    } on LocalDataException catch (error) {
      return Future<String>.error(error);
    } on Object {
      return Future<String>.error(
        const AiException(
          AiErrorKind.input,
          'اطلاعات درخواست قابل پردازش نیست.',
        ),
      );
    }
  }

  /// Requests cancellation.
  ///
  /// Returns false when no cancellable operation is registered.
  /// A cancellation arriving after durable completion does not undo it.
  bool cancel(String requestId) {
    final request = _inFlight[requestId];

    if (request == null || request.abort.isCompleted) {
      return false;
    }

    request.abort.complete();
    return true;
  }

  void _checkCancelled(Completer<void> abort) {
    if (abort.isCompleted || _disposed) {
      throw const AiException(AiErrorKind.cancelled, 'درخواست لغو شد.');
    }
  }

  Future<String> _execute({
    required List<Map<String, String>> messages,
    required String question,
    required String id,
    required Completer<void> abort,
    required bool jsonMode,
  }) async {
    final ledger = store;

    var reserved = false;
    var requestStarted = false;
    var answerReceived = false;

    try {
      _checkCancelled(abort);

      if (ledger?.walletError != null) {
        throw LocalDataException(ledger!.walletError!);
      }

      // Recover a durable answer without requiring network configuration
      // or new credits.
      //
      // prepareAiRequest must verify that the same ID belongs to the
      // same question. Do not return savedAiAnswer directly.
      if (ledger != null && ledger.savedAiAnswer(id) != null) {
        final reservation = await ledger.prepareAiRequest(
          id: id,
          question: question,
        );

        if (reservation.isCompleted) {
          final cached = reservation.cachedAnswer;

          if (cached == null ||
              cached.trim().isEmpty ||
              cached.length > EducationStore.maxAnswerLength) {
            throw const AiException(
              AiErrorKind.storage,
              'پاسخ ذخیره‌شده معتبر نیست. '
              'تاریخچه مشاوره را بررسی کن.',
            );
          }

          return cached;
        }

        // The ledger state changed during recovery.
        reserved = true;
      }

      _checkCancelled(abort);
      _validateConfiguration();

      if (ledger != null && !reserved && !ledger.canUseAi) {
        throw const AiException(
          AiErrorKind.credits,
          'پر سیمرغ کافی نداری. '
          'برای ادامه، یک بسته پر تهیه کن.',
        );
      }

      final payload = <String, Object?>{
        'model': model,
        'messages': messages,
        'temperature': temperature,
        'max_tokens': maxTokens,
        if (disableDeepSeekThinking) 'thinking': const {'type': 'disabled'},
        if (jsonMode) 'response_format': const {'type': 'json_object'},
      };

      final body = utf8.encode(jsonEncode(payload));

      if (body.length > maxRequestBytes) {
        throw const AiException(
          AiErrorKind.input,
          'حجم درخواست زیاد است. '
          'پرسش یا اطلاعات گفت‌وگو را کوتاه‌تر کن.',
        );
      }

      _checkCancelled(abort);

      if (ledger != null && !reserved) {
        final reservation = await ledger.prepareAiRequest(
          id: id,
          question: question,
        );

        if (reservation.isCompleted) {
          final cached = reservation.cachedAnswer;

          if (cached == null ||
              cached.trim().isEmpty ||
              cached.length > EducationStore.maxAnswerLength) {
            throw const AiException(
              AiErrorKind.storage,
              'پاسخ ذخیره‌شده معتبر نیست.',
            );
          }

          return cached;
        }

        reserved = true;
      }

      _checkCancelled(abort);

      requestStarted = true;

      final answer = await _post(_endpoint(), body, abort);

      answerReceived = true;

      // Cancellation is honored before entering durable completion.
      // Once completion starts, do not race it against cancellation.
      _checkCancelled(abort);

      if (ledger != null) {
        await ledger.completeAiRequest(id, answer);
      }

      return answer;
    } on Object catch (error) {
      if (reserved && ledger != null) {
        try {
          // The store must make this operation idempotent and avoid
          // refunding a request already durably completed.
          await ledger.refundAiRequest(id);
        } on Object {
          throw const AiException(
            AiErrorKind.storage,
            'درخواست کامل نشد و ثبت بازپرداخت نیز تأیید نشد. '
            'کیف اعتبار و تاریخچه مشاوره را بررسی کن؛ '
            'از پاک‌کردن داده‌های برنامه خودداری کن.',
          );
        }
      }

      if (error is AiException || error is LocalDataException) {
        rethrow;
      }

      if (!requestStarted || answerReceived) {
        throw const AiException(
          AiErrorKind.storage,
          'ثبت اطلاعات یا نتیجه درخواست انجام نشد. '
          'تاریخچه مشاوره را بررسی کن و دوباره تلاش کن.',
        );
      }

      throw const AiException(
        AiErrorKind.network,
        'ارتباط با مشاور برقرار نشد. '
        'اتصال اینترنت را بررسی کن.',
      );
    }
  }

  List<Map<String, String>> _messages(
    Map<String, dynamic>? profile,
    List<Map<String, dynamic>> history,
    String question, {
    String? systemInstruction,
  }) {
    final approvedProfile = profile?['aiProfileContextConsent'] == true
        ? profile
        : null;

    String field(String key, int limit) {
      final raw = approvedProfile?[key];

      // Do not stringify arbitrary objects from damaged profile records.
      if (raw is! String) return '';

      final value = raw
          .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ')
          .trim();

      return _safeTruncate(value, limit);
    }

    // Explicit allowlist: name, nickname, contact information,
    // wallet data and arbitrary profile keys are not included.
    final context =
        jsonEncode(
              approvedProfile == null
                  ? <String, Object?>{'consent': false}
                  : <String, Object?>{
                      'consent': true,
                      'grade': field('grade', 80),
                      'year': field('year', 80),
                      'field': field('field', 120),
                      'goal': field('goal', 300),
                    },
            )
            .replaceAll('<', r'\u003c')
            .replaceAll('>', r'\u003e')
            .replaceAll('&', r'\u0026');

    final recent = <Map<String, String>>[];
    var budget = _maxHistoryChars;

    for (final message in history.reversed) {
      final role = message['role'];
      final content = message['content'];

      if ((role != 'user' && role != 'assistant') ||
          content is! String ||
          content.trim().isEmpty ||
          message['status'] == 'failed' ||
          message['status'] == 'pending') {
        continue;
      }

      final limit = role == 'assistant'
          ? EducationStore.maxAnswerLength
          : EducationStore.maxQuestionLength;

      if (content.length > limit) continue;
      if (budget <= 0) break;

      final retained = _safeTruncate(content, budget);

      if (retained.isEmpty) break;

      recent.add({'role': role as String, 'content': retained});

      budget -= retained.length;

      if (recent.length >= _maxHistoryMessages) break;
    }

    final systemContent = buildSimorghSystemPrompt(
      studentContext: context,
      grade: field('grade', 80),
    );

    final instruction = systemInstruction?.trim();

    final merged = instruction == null || instruction.isEmpty
        ? systemContent
        : '$systemContent\n\n'
              'دستور ویژه این نوبت آموزشی:\n$instruction';

    return [
      {'role': 'system', 'content': merged},
      ...recent.reversed,
      {'role': 'user', 'content': question},
    ];
  }

  /// Truncate without splitting a UTF-16 surrogate pair.
  static String _safeTruncate(String value, int maximum) {
    if (maximum <= 0) return '';
    if (value.length <= maximum) return value;

    var end = maximum;

    if (_isHighSurrogate(value.codeUnitAt(end - 1))) {
      end--;
    }

    return value.substring(0, end);
  }

  static bool _isHighSurrogate(int value) {
    return value >= 0xD800 && value <= 0xDBFF;
  }

  Future<String> _post(Uri uri, List<int> body, Completer<void> abort) async {
    _checkCancelled(abort);

    final result = Completer<String>();

    StreamSubscription<List<int>>? subscription;
    var finished = false;

    Future<void> cancelSubscription() async {
      final current = subscription;
      subscription = null;

      if (current == null) return;

      try {
        await current.cancel();
      } on Object {
        // Never replace the already selected result with cleanup errors.
      }
    }

    void stopTransport() {
      if (!abort.isCompleted) {
        abort.complete();
      }

      unawaited(cancelSubscription());
    }

    void fail(AiException error) {
      if (finished) return;

      finished = true;
      result.completeError(error);
      stopTransport();
    }

    void succeed(String answer) {
      if (finished) return;

      finished = true;
      result.complete(answer);
    }

    final timer = Timer(timeout, () {
      fail(
        const AiException(
          AiErrorKind.timeout,
          'پاسخ به‌موقع نرسید. '
          'اتصال اینترنت را بررسی کن و دوباره تلاش کن.',
        ),
      );
    });

    // Explicit cancellation completes the public Future even when a
    // custom HTTP client does not promptly interrupt its response stream.
    unawaited(
      abort.future.then((_) {
        fail(const AiException(AiErrorKind.cancelled, 'درخواست لغو شد.'));
      }),
    );

    Future<void> receive() async {
      try {
        if (finished) return;

        final request =
            http.AbortableRequest('POST', uri, abortTrigger: abort.future)
              ..followRedirects = false
              ..headers.addAll({
                'Authorization': 'Bearer $apiKey',
                'Content-Type': 'application/json; charset=utf-8',
                'Accept': 'application/json',
              })
              ..bodyBytes = body;

        final response = await client.send(request);

        if (finished) {
          // A late response must not remain subscribed or be parsed.
          try {
            await response.stream.listen((_) {}).cancel();
          } on Object {
            // Cleanup only.
          }
          return;
        }

        final statusError = _statusError(response.statusCode);
        final declaredLength = response.contentLength;

        if (statusError != null ||
            (declaredLength != null && declaredLength > maxResponseBytes)) {
          final error =
              statusError ??
              const AiException(
                AiErrorKind.response,
                'حجم پاسخ دریافتی بیش از حد مجاز است.',
              );

          fail(error);

          try {
            await response.stream.listen((_) {}).cancel();
          } on Object {
            // Cleanup only.
          }
          return;
        }

        final bytes = BytesBuilder(copy: false);

        subscription = response.stream.listen(
          (chunk) {
            if (finished) return;

            if (chunk.length > maxResponseBytes - bytes.length) {
              fail(
                const AiException(
                  AiErrorKind.response,
                  'حجم پاسخ دریافتی بیش از حد مجاز است.',
                ),
              );
              return;
            }

            bytes.add(chunk);
          },
          onError: (Object _) {
            if (abort.isCompleted) {
              fail(const AiException(AiErrorKind.cancelled, 'درخواست لغو شد.'));
            } else {
              fail(
                const AiException(
                  AiErrorKind.network,
                  'دریافت پاسخ کامل نشد. '
                  'اتصال اینترنت را بررسی کن.',
                ),
              );
            }
          },
          onDone: () {
            if (finished) return;

            try {
              succeed(_parse(bytes.takeBytes()));
            } on AiException catch (error) {
              fail(error);
            } on Object {
              fail(
                const AiException(
                  AiErrorKind.response,
                  'پاسخ معتبری از مشاور دریافت نشد.',
                ),
              );
            }
          },
          cancelOnError: true,
        );

        // Handles cancellation racing with stream subscription setup.
        if (finished) {
          await cancelSubscription();
        }
      } on Object {
        if (finished) return;

        fail(
          abort.isCompleted
              ? const AiException(AiErrorKind.cancelled, 'درخواست لغو شد.')
              : const AiException(
                  AiErrorKind.network,
                  'ارتباط با مشاور برقرار نشد. '
                  'اتصال اینترنت را بررسی کن.',
                ),
        );
      }
    }

    unawaited(receive());

    try {
      return await result.future;
    } finally {
      timer.cancel();
      await cancelSubscription();
    }
  }

  AiException? _statusError(int status) {
    if (status >= 200 && status < 300) return null;

    if (status == 429) {
      return const AiException(
        AiErrorKind.rateLimit,
        'تعداد درخواست‌ها زیاد شده است. '
        'کمی بعد دوباره تلاش کن.',
      );
    }

    if (status == 401 || status == 403) {
      return const AiException(
        AiErrorKind.configuration,
        'دسترسی سرویس مشاور تأیید نشد. '
        'تنظیمات انتشار نیاز به بررسی دارد.',
      );
    }

    if (status == 404) {
      return const AiException(
        AiErrorKind.configuration,
        'نشانی سرویس یا مدل پاسخ‌گویی در دسترس نیست.',
      );
    }

    if (status == 400 || status == 413 || status == 422) {
      return const AiException(
        AiErrorKind.input,
        'درخواست برای سرویس قابل پردازش نبود. '
        'ممکن است حجم یا تنظیمات درخواست نیاز به اصلاح داشته باشد.',
      );
    }

    if (status == 408 || status == 504) {
      return const AiException(
        AiErrorKind.timeout,
        'سرویس پاسخ را به‌موقع آماده نکرد. '
        'کمی بعد دوباره تلاش کن.',
      );
    }

    if (status >= 300 && status < 400) {
      return const AiException(
        AiErrorKind.configuration,
        'نشانی سرویس تغییر مسیر داد. '
        'برای حفاظت از کلید دسترسی، درخواست متوقف شد.',
      );
    }

    return const AiException(
      AiErrorKind.server,
      'سرویس مشاور موقتاً پاسخ نداد. '
      'کمی بعد دوباره تلاش کن.',
    );
  }

  String _parse(List<int> bytes) {
    try {
      if (bytes.isEmpty || bytes.length > maxResponseBytes) {
        throw const FormatException();
      }

      final Object? data = jsonDecode(
        utf8.decode(bytes, allowMalformed: false),
      );

      if (data is! Map ||
          data['error'] != null ||
          data['choices'] is! List ||
          (data['choices'] as List).isEmpty) {
        throw const FormatException();
      }

      final Object? choice = (data['choices'] as List).first;

      if (choice is! Map || choice['message'] is! Map) {
        throw const FormatException();
      }

      final finishReason = choice['finish_reason'];

      // Accept providers omitting finish_reason, but reject explicit
      // truncation, tool calls, filtering and other non-final answers.
      if (finishReason != null && finishReason != 'stop') {
        throw const FormatException();
      }

      final message = choice['message'] as Map;
      final Object? content = message['content'];

      if (content is! String ||
          content.trim().isEmpty ||
          content.length > EducationStore.maxAnswerLength ||
          message['tool_calls'] != null ||
          message['function_call'] != null) {
        throw const FormatException();
      }

      return content.trim();
    } on Object {
      throw const AiException(
        AiErrorKind.response,
        'پاسخ کامل و معتبری از مشاور دریافت نشد. '
        'وضعیت درخواست و اعتبار در برنامه بررسی می‌شود.',
      );
    }
  }

  void dispose() {
    if (_disposed) return;

    _disposed = true;

    for (final request in _inFlight.values.toList()) {
      if (!request.abort.isCompleted) {
        request.abort.complete();
      }
    }

    // Entries are removed when their Futures finish, after ledger cleanup.
    if (_ownsClient) {
      client.close();
    }
  }
}
