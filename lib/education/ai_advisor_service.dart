import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'education_store.dart';

/// سرویس ارتباط با هوش مصنوعی (OpenAI-compatible API)
class AiAdvisorService {
  AiAdvisorService({
    http.Client? client,
    String? apiKey,
    String? endpoint,
    String? model,
    this.store,
    this.temperature = 0.55,
    this.maxTokens = 1200,
    this.maxRetries = 2,
  })  : client = client ?? http.Client(),
        apiKey = apiKey ?? const String.fromEnvironment('AI_API_KEY'),
        endpoint = endpoint ??
            const String.fromEnvironment(
              'AI_API_ENDPOINT',
              defaultValue: 'https://api.avalai.ir/v1/chat/completions',
            ),
        model = model ??
            const String.fromEnvironment(
              'AI_MODEL',
              defaultValue: 'deepseek-chat',
            );

  final EducationStore? store;
  final http.Client client;
  final String apiKey;
  final String endpoint;
  final String model;
  final double temperature;
  final int maxTokens;
  final int maxRetries;

  // ── System Prompt ثابت (یک‌بار تخصیص) ──
  static const _systemPrompt = '''
تو مشاور هوشمند تحصیلی برای دانش‌آموزان ایرانی هستی.
همیشه فارسی روان و متناسب با سن پاسخ بده.
در آموزش مرحله‌به‌مرحله توضیح بده.
در برنامه‌ریزی، استراحت و توان واقعی را لحاظ کن.
در انتخاب رشته حکم قطعی صادر نکن و اطلاعات متغیر را بدون منبع رسمی قطعی جلوه نده.
اطلاعات هویتی، نشانی، شماره تماس، رمز یا اطلاعات حساس درخواست نکن.
پاسخ پزشکی، تشخیص روان‌شناختی یا درمان ارائه نده.
اگر دانش‌آموز از خطر فوری، آزار یا آسیب به خود صحبت کرد، با همدلی پاسخ بده و او را به گفت‌وگو با والد یا بزرگسال مورد اعتماد و خدمات اضطراری محل زندگی‌اش راهنمایی کن.
هیچ رشته یا آینده‌ای را تضمین نکن و در صورت نامطمئن بودن، صریح بگو.''';

  /// ارسال سؤال به هوش مصنوعی و دریافت پاسخ
  Future<String> ask({
    required Map<String, dynamic>? profile,
    required List<Map<String, dynamic>> history,
    required String question,
  }) async {
    // ── پیش‌بررسی‌ها ──
    if (store != null && !store!.canUseAi) {
      throw AiException(
        'اعتبار رایگان شما تمام شده است. برای ادامه، بسته اعتبار تهیه کنید.',
        type: AiErrorType.quotaExceeded,
      );
    }

    if (apiKey.trim().isEmpty) {
      throw AiException(
        'سرویس هوش مصنوعی هنوز برای این نسخه پیکربندی نشده است. '
        'سایر امکانات برنامه به‌صورت آفلاین در دسترس‌اند.',
        type: AiErrorType.notConfigured,
      );
    }

    // ── ساخت پیام‌ها ──
    final messages = _buildMessages(profile, history, question);

    // ── ارسال با retry ──
    Exception? lastError;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final answer = await _sendRequest(messages);

        // ثبت مصرف اعتبار (شکست این مرحله پاسخ را باطل نمی‌کند)
        if (store != null) {
          try {
            await store!.recordSuccessfulAiUse();
          } catch (e) {
            debugPrint('⚠️ ثبت مصرف اعتبار ناموفق: $e');
          }
        }

        return answer;
      } on AiException {
        rethrow; // خطاهای منطقی (quota, config) retry نمی‌شوند
      } on http.ClientException catch (e) {
        lastError = e;
        debugPrint('⚠️ خطای شبکه (تلاش ${attempt + 1}/${maxRetries + 1}): $e');
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: (attempt + 1) * 2));
        }
      } on Exception catch (e) {
        lastError = e;
        debugPrint('⚠️ خطای سرویس (تلاش ${attempt + 1}/${maxRetries + 1}): $e');
        if (attempt < maxRetries) {
          await Future.delayed(Duration(seconds: (attempt + 1) * 2));
        }
      }
    }

    throw AiException(
      'اتصال اینترنت یا سرویس هوش مصنوعی در دسترس نیست.',
      type: AiErrorType.network,
      cause: lastError,
    );
  }

  /// ساخت لیست پیام‌ها برای API
  List<Map<String, String>> _buildMessages(
    Map<String, dynamic>? profile,
    List<Map<String, dynamic>> history,
    String question,
  ) {
    final context = profile == null
        ? 'پروفایل ثبت نشده'
        : 'مقطع: ${profile['grade'] ?? ''}'
            '؛ رشته: ${profile['field'] ?? ''}'
            '؛ هدف: ${profile['goal'] ?? 'اعلام نشده'}';

    return [
      {
        'role': 'system',
        'content': '$_systemPrompt اطلاعات دانش‌آموز: $context.',
      },
      // آخرین ۲۴ پیام تاریخچه (بهینه بدون ساخت لیست‌های موقت اضافی)
      for (final m in history.length > 24
          ? history.sublist(history.length - 24)
          : history)
        if (m['role'] == 'user' || m['role'] == 'assistant')
          {
            'role': m['role'].toString(),
            'content': m['content'].toString(),
          },
      {'role': 'user', 'content': question},
    ];
  }

  /// ارسال درخواست HTTP و پردازش پاسخ
  Future<String> _sendRequest(List<Map<String, String>> messages) async {
    final response = await client
        .post(
          Uri.parse(endpoint),
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'model': model,
            'messages': messages,
            'temperature': temperature,
            'max_tokens': maxTokens,
          }),
        )
        .timeout(const Duration(seconds: 45));

    // ── بررسی کد وضعیت ──
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = switch (response.statusCode) {
        401 => 'کلید API نامعتبر است.',
        403 => 'دسترسی به سرویس مجاز نیست.',
        429 => 'تعداد درخواست‌ها زیاد شده است. کمی بعد دوباره تلاش کنید.',
        500 || 502 || 503 => 'سرویس هوش مصنوعی موقتاً در دسترس نیست.',
        _ => 'ارتباط با مشاور برقرار نشد. کد خطا: ${response.statusCode}',
      };
      throw AiException(message, type: AiErrorType.api);
    }

    // ── پردازش پاسخ ──
    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final choices = data['choices'] as List<dynamic>?;

    if (choices == null || choices.isEmpty) {
      throw AiException('پاسخ معتبری دریافت نشد.', type: AiErrorType.emptyResponse);
    }

    final message = (choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>?;
    final answer = message?['content']?.toString().trim() ?? '';

    if (answer.isEmpty) {
      throw AiException('پاسخ خالی از سرویس دریافت شد.', type: AiErrorType.emptyResponse);
    }

    return answer;
  }

  void dispose() => client.close();
}

// ═══════════════════════════════════════════════════════════
//  Exception سفارشی با نوع خطا
// ═══════════════════════════════════════════════════════════

enum AiErrorType {
  quotaExceeded,
  notConfigured,
  network,
  api,
  emptyResponse,
  unknown,
}

class AiException implements Exception {
  AiException(this.message, {this.type = AiErrorType.unknown, this.cause});

  final String message;
  final AiErrorType type;
  final Object? cause;

  @override
  String toString() => 'AiException($type): $message';
}
