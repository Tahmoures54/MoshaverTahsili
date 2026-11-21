import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'education_store.dart';
import 'ai_safety_policy.dart';
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
  /// User-initiated cancellation; the reserved feather is refunded.
  cancelled,
}

/// Only fixed, non-sensitive messages reach the UI or local chat history.
/// Never include response bodies, headers, credentials or purchase tokens.
class AiException implements Exception {
  const AiException(this.kind, this.message);
  final AiErrorKind kind;
  final String message;
  @override
  String toString() => message;
}

/// Small, typed handle for an in-flight request.
class _InFlightRequest {
  const _InFlightRequest(this.question, this.future);
  final String question;
  final Future<String> future;
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
  })  : _ownsClient = client == null,
        client = client ?? http.Client(),
        apiKey = (apiKey ?? const String.fromEnvironment('AI_API_KEY')).trim(),
        endpoint = endpoint ??
            const String.fromEnvironment('AI_API_ENDPOINT',
                defaultValue: 'https://api.avalai.ir/v1'),
        model = model ??
            const String.fromEnvironment('AI_MODEL',
                defaultValue: 'deepseek-chat');

  final EducationStore? store;
  final bool _ownsClient;
  final http.Client client;
  final String apiKey, endpoint, model;
  final Duration timeout;
  final double temperature;
  final int maxTokens;

  static const maxRequestBytes = 96 * 1024;
  static const maxResponseBytes = 512 * 1024;
  static const _maxHistoryChars = 18000;
  static const _maxHistoryMessages = 24;

  final Map<String, _InFlightRequest> _inFlight = {};
  final Map<String, Completer<void>> _aborts = {};
  Uri? _cachedEndpoint;
  bool? _cachedConfigured;
  bool _disposed = false;

  bool get isRunning => _inFlight.isNotEmpty;
  int get activeRequestCount => _inFlight.length;

  /// Returns true only when the API key is present **and** the configured
  /// endpoint passes validation, so the UI never shows “ready” for a
  /// configuration that will fail on the first network call.
  bool get isConfigured {
    final cached = _cachedConfigured;
    if (cached != null) return cached;
    if (apiKey.isEmpty) return _cachedConfigured = false;
    try {
      _endpoint();
      return _cachedConfigured = true;
    } on Object {
      return _cachedConfigured = false;
    }
  }

  Uri _endpoint() {
    final cached = _cachedEndpoint;
    if (cached != null) return cached;
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const AiException(AiErrorKind.configuration,
          'نشانی سرویس پاسخ‌گویی در این نسخه معتبر نیست.');
    }
    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    return _cachedEndpoint = uri.replace(
      path: path.endsWith('/chat/completions') ? path : '$path/chat/completions',
    );
  }

  /// Sends one request. Idempotent under the same [requestId]: concurrent
  /// callers with the same id share one network call. Pass [jsonMode] to
  /// request a strict `{ "response_format": { "type": "json_object" } }`
  /// response from providers that support it.
  Future<String> ask({
    required Map<String, dynamic>? profile,
    required List<Map<String, dynamic>> history,
    required String question,
    String? requestId,
    String? systemInstruction,
    bool jsonMode = false,
  }) {
    if (_disposed) {
      throw const AiException(
          AiErrorKind.configuration, 'سرویس مشاور بسته شده است.');
    }
    final id = requestId ??
        'ai-${DateTime.now().microsecondsSinceEpoch}-${identityHashCode(question)}';
    final normalizedQuestion = question.trim();
    final active = _inFlight[id];
    if (active != null) {
      if (active.question != normalizedQuestion) {
        return Future<String>.error(const AiException(AiErrorKind.input,
            'شناسه این درخواست هم‌زمان برای پرسش دیگری استفاده شده است.'));
      }
      return active.future;
    }
    final abort = Completer<void>();
    _aborts[id] = abort;
    final future = _execute(
      profile,
      history,
      normalizedQuestion,
      id,
      abort: abort,
      systemInstruction: systemInstruction,
      jsonMode: jsonMode,
    );
    final tracked = future.whenComplete(() {
      _inFlight.remove(id);
      _aborts.remove(id);
    });
    _inFlight[id] = _InFlightRequest(normalizedQuestion, tracked);
    return tracked;
  }

  /// Cancels an in-flight request. The original [ask] future completes with
  /// an [AiErrorKind.cancelled] exception and the reserved feather is refunded.
  bool cancel(String requestId) {
    final abort = _aborts.remove(requestId);
    if (abort == null || abort.isCompleted) return false;
    abort.complete();
    return true;
  }

  Future<String> _execute(
    Map<String, dynamic>? profile,
    List<Map<String, dynamic>> history,
    String question,
    String id, {
    required Completer<void> abort,
    String? systemInstruction,
    bool jsonMode = false,
  }) async {
    if (question.isEmpty || question.length > EducationStore.maxQuestionLength) {
      throw const AiException(
          AiErrorKind.input, 'پرسش باید بین ۱ تا ۴۰۰۰ نویسه باشد.');
    }
    // Explicit crisis-intent phrases are handled locally before checking the
    // provider key, wallet, or constructing any network request.
    final safety = AiSafetyPolicy.assessTurn(question, history);
    if (safety.shouldBlockRemoteAi) return safety.localResponse!;
    if (!isConfigured) {
      throw const AiException(AiErrorKind.configuration,
          'گفت‌وگوی سیمرغ هنوز آماده استفاده نیست. امکانات محلی برنامه همچنان در دسترس‌اند.');
    }
    final uri = _endpoint();
    if (store?.walletError != null) {
      throw LocalDataException(store!.walletError!);
    }
    if (store != null &&
        !store!.canUseAi &&
        store!.savedAiAnswer(id) == null) {
      throw const AiException(AiErrorKind.credits,
          'پر سیمرغ کافی نداری. برای ادامه، یک بسته پر تهیه کن.');
    }
    final messages = _messages(profile, history, question,
        systemInstruction: systemInstruction);

    final isDeepSeek = model.toLowerCase().contains('deepseek');
    final payload = <String, Object?>{
      'model': model,
      'messages': messages,
      'temperature': temperature,
      'max_tokens': maxTokens,
      // Only DeepSeek honours this flag; unknown providers would reject it.
      if (isDeepSeek) 'thinking': const {'type': 'disabled'},
      if (jsonMode) 'response_format': const {'type': 'json_object'},
    };
    final body = utf8.encode(jsonEncode(payload));
    if (body.length > maxRequestBytes) {
      throw const AiException(AiErrorKind.input,
          'حجم درخواست زیاد است. پرسش یا اطلاعات گفت‌وگو را کوتاه‌تر کن.');
    }

    var reserved = false;
    var requestStarted = false;
    var answerReceived = false;
    try {
      if (store != null) {
        final reservation =
            await store!.prepareAiRequest(id: id, question: question);
        if (reservation.isCompleted) return reservation.cachedAnswer!;
        reserved = true;
      }
      requestStarted = true;
      final answer = await _post(uri, body, abort);
      answerReceived = true;
      if (store != null) await store!.completeAiRequest(id, answer);
      return answer;
    } on Object catch (error) {
      if (reserved) {
        try {
          await store!.refundAiRequest(id);
        } on Object {
          // The pending reservation survives a storage failure and is refunded
          // on the next startup. Never silently replace a damaged wallet.
        }
      }
      if (error is AiException || error is LocalDataException) rethrow;
      if (!requestStarted || answerReceived) {
        throw const AiException(AiErrorKind.storage,
            'ذخیره نتیجه درخواست انجام نشد. کمی بعد دوباره تلاش کن.');
      }
      throw const AiException(AiErrorKind.network,
          'ارتباط با مشاور برقرار نشد. اتصال اینترنت را بررسی کن.');
    }
  }

  List<Map<String, String>> _messages(
    Map<String, dynamic>? profile,
    List<Map<String, dynamic>> history,
    String question, {
    String? systemInstruction,
  }) {
    // Profile context is opt-in. Legacy profiles and backups without this flag
    // remain private by default; nickname is never included in the AI context.
    final approvedProfile =
        profile?['aiProfileContextConsent'] == true ? profile : null;
    String field(String key, int limit) {
      final value = approvedProfile?[key]?.toString().trim() ?? '';
      return value.length <= limit ? value : _safeTruncate(value, limit);
    }

    final context = approvedProfile == null
        ? '{"consent":false}'
        : jsonEncode({
            'consent': true,
            'grade': field('grade', 80),
            'year': field('year', 80),
            'field': field('field', 120),
            'goal': field('goal', 300),
          })
            .replaceAll('<', r'\u003c')
            .replaceAll('>', r'\u003e')
            .replaceAll('&', r'\u0026');

    final recent = <Map<String, String>>[];
    var budget = _maxHistoryChars;
    for (final message in history.reversed) {
      final role = message['role'];
      final content = message['content'];
      final maxMessageLength = role == 'assistant'
          ? EducationStore.maxAnswerLength
          : EducationStore.maxQuestionLength;
      if ((role != 'user' && role != 'assistant') ||
          content is! String ||
          content.isEmpty ||
          content.length > maxMessageLength ||
          message['status'] == 'failed' ||
          message['status'] == 'pending') {
        continue;
      }
      if (budget <= 0) break;
      final retained =
          content.length > budget ? _safeTruncate(content, budget) : content;
      budget -= retained.length;
      recent.add({'role': role as String, 'content': retained});
      if (recent.length == _maxHistoryMessages) break;
    }

    final systemContent = buildSimorghSystemPrompt(
      studentContext: context,
      grade: field('grade', 80),
    );
    final merged = systemInstruction == null
        ? systemContent
        : '$systemContent\n\nدستور ویژه این نوبت آموزشی:\n$systemInstruction';

    return [
      {'role': 'system', 'content': merged},
      ...recent.reversed,
      {'role': 'user', 'content': question},
    ];
  }

  /// Truncates a string without breaking a UTF-16 surrogate pair, so
  /// multi-byte characters (emoji, some symbols) never corrupt JSON payloads.
  static String _safeTruncate(String value, int max) {
    if (value.length <= max) return value;
    var end = max;
    if (end > 0 && _isHighSurrogate(value.codeUnitAt(end - 1))) end -= 1;
    return value.substring(0, end);
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

  Future<String> _post(
    Uri uri,
    List<int> body,
    Completer<void> abort,
  ) async {
    if (abort.isCompleted) {
      throw const AiException(
          AiErrorKind.cancelled, 'درخواست پیش از پایان لغو شد.');
    }
    http.StreamedResponse? response;
    StreamSubscription<List<int>>? subscription;
    var subscriptionCancelled = false;

    Future<void> cancelSubscription() async {
      if (subscriptionCancelled) return;
      subscriptionCancelled = true;
      try {
        await subscription?.cancel();
      } on Object {
        // The user-visible error state is already decided.
      }
    }

    Future<String> receive() async {
      // AbortableRequest lets a timeout, dispose, or explicit cancel stop the
      // underlying transport instead of merely stopping the wait.
      final request =
          http.AbortableRequest('POST', uri, abortTrigger: abort.future)
            ..headers.addAll({
              'Authorization': 'Bearer $apiKey',
              'Content-Type': 'application/json; charset=utf-8',
              'Accept': 'application/json',
            })
            ..bodyBytes = body;
      response = await client.send(request);
      final status = response!.statusCode;
      if (status == 429) {
        throw const AiException(AiErrorKind.rateLimit,
            'تعداد درخواست‌ها زیاد شده است. کمی بعد دوباره تلاش کن.');
      }
      if (status == 401 || status == 403) {
        throw const AiException(AiErrorKind.configuration,
            'دسترسی سرویس مشاور تأیید نشد. تنظیمات انتشار نیاز به بررسی دارد.');
      }
      if (status == 400 || status == 422) {
        throw const AiException(AiErrorKind.input,
            'درخواست برای سرویس قابل پردازش نبود. پرسش یا اطلاعات گفت‌وگو را کوتاه‌تر کن.');
      }
      if (status < 200 || status >= 300) {
        throw const AiException(AiErrorKind.server,
            'سرویس مشاور موقتاً پاسخ نداد. کمی بعد دوباره تلاش کن.');
      }
      final length = response!.contentLength;
      if (length != null && length > maxResponseBytes) {
        throw const AiException(
            AiErrorKind.response, 'حجم پاسخ دریافتی بیش از حد مجاز است.');
      }
      final completer = Completer<List<int>>();
      final bytes = BytesBuilder(copy: false);
      subscription = response!.stream.listen(
        (chunk) {
          if (completer.isCompleted) return;
          if (bytes.length + chunk.length > maxResponseBytes) {
            completer.completeError(const AiException(
                AiErrorKind.response, 'حجم پاسخ دریافتی بیش از حد مجاز است.'));
            unawaited(cancelSubscription());
            return;
          }
          bytes.add(chunk);
        },
        onError: (Object _) {
          if (!completer.isCompleted) {
            completer.completeError(const AiException(AiErrorKind.network,
                'دریافت پاسخ کامل نشد. اتصال اینترنت را بررسی کن.'));
          }
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(bytes.takeBytes());
        },
        cancelOnError: true,
      );
      return _parse(await completer.future);
    }

    try {
      return await receive().timeout(timeout);
    } on TimeoutException {
      if (!abort.isCompleted) abort.complete();
      throw const AiException(AiErrorKind.timeout,
          'پاسخ به‌موقع نرسید. اتصال اینترنت را بررسی کن و دوباره تلاش کن.');
    } on AiException {
      rethrow;
    } on Object {
      if (abort.isCompleted) {
        // Completed via `cancel()` or `dispose()`.
        throw const AiException(
            AiErrorKind.cancelled, 'درخواست پیش از پایان لغو شد.');
      }
      // Exception details may contain URLs or credentials; do not expose them.
      throw const AiException(AiErrorKind.network,
          'ارتباط با مشاور برقرار نشد. اتصال اینترنت را بررسی کن.');
    } finally {
      await cancelSubscription();
    }
  }

  String _parse(List<int> bytes) {
    try {
      final Object? data = jsonDecode(utf8.decode(bytes));
      if (data is! Map ||
          data['choices'] is! List ||
          (data['choices'] as List).isEmpty) {
        throw const FormatException('Missing choices');
      }
      final Object? choice = (data['choices'] as List).first;
      if (choice is! Map || choice['message'] is! Map) {
        throw const FormatException('Missing message');
      }
      final Object? content = (choice['message'] as Map)['content'];
      if (content is! String ||
          content.trim().isEmpty ||
          content.length > EducationStore.maxAnswerLength) {
        throw const FormatException('Invalid content');
      }
      return content.trim();
    } on Object {
      throw const AiException(AiErrorKind.response,
          'پاسخ معتبری از مشاور دریافت نشد؛ پر رزروشده به کیسه‌ات بازمی‌گردد.');
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final abort in _aborts.values.toList()) {
      if (!abort.isCompleted) abort.complete();
    }
    _aborts.clear();
    if (_ownsClient) client.close();
  }
}
