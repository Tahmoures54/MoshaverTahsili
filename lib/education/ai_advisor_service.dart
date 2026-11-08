import 'dart:convert';
import 'package:http/http.dart' as http;

class AiAdvisorService {
  AiAdvisorService({http.Client? client}) : client = client ?? http.Client();
  final http.Client client;

  static const apiKey = String.fromEnvironment('AI_API_KEY');
  static const endpoint = String.fromEnvironment(
    'AI_API_ENDPOINT',
    defaultValue: 'https://api.avalai.ir/v1/chat/completions',
  );
  static const model = String.fromEnvironment('AI_MODEL', defaultValue: 'deepseek-chat');

  Future<String> ask({
    required Map<String, dynamic>? profile,
    required List<Map<String, dynamic>> history,
    required String question,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw Exception('سرویس هوش مصنوعی هنوز برای این نسخه پیکربندی نشده است. سایر امکانات برنامه به‌صورت آفلاین در دسترس‌اند.');
    }
    final context = profile == null ? 'پروفایل ثبت نشده' :
        'مقطع: ' + (profile['grade'] ?? '').toString() +
        '؛ رشته: ' + (profile['field'] ?? '').toString() +
        '؛ هدف: ' + (profile['goal'] ?? 'اعلام نشده').toString();
    final messages = <Map<String, String>>[
      {
        'role': 'system',
        'content': 'تو مشاور هوشمند تحصیلی برای دانش‌آموزان ایرانی هستی. همیشه فارسی روان و متناسب با سن پاسخ بده. ' +
          'اطلاعات دانش‌آموز: ' + context + '. در آموزش مرحله‌به‌مرحله توضیح بده. در برنامه‌ریزی استراحت و توان واقعی را لحاظ کن. ' +
          'در انتخاب رشته حکم قطعی صادر نکن و اطلاعات متغیر را بدون منبع رسمی قطعی جلوه نده. ' +
          'اطلاعات شخصی غیرضروری درخواست نکن. پاسخ پزشکی یا روان‌درمانی نده.'
      },
      ...history.where((m) => m['role'] == 'user' || m['role'] == 'assistant')
          .take(24)
          .map((m) => {'role': m['role'].toString(), 'content': m['content'].toString()}),
      {'role': 'user', 'content': question},
    ];
    try {
      final response = await client.post(
        Uri.parse(endpoint),
        headers: {'Authorization': 'Bearer ' + apiKey, 'Content-Type': 'application/json'},
        body: jsonEncode({'model': model, 'messages': messages, 'temperature': 0.55, 'max_tokens': 1200}),
      ).timeout(const Duration(seconds: 45));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(response.statusCode == 429
            ? 'تعداد درخواست‌ها زیاد شده است. کمی بعد دوباره تلاش کنید.'
            : 'ارتباط با مشاور برقرار نشد. کد خطا: ' + response.statusCode.toString());
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) throw Exception('پاسخ معتبری دریافت نشد.');
      final message = (choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>?;
      final answer = message?['content']?.toString().trim() ?? '';
      if (answer.isEmpty) throw Exception('پاسخ خالی از سرویس دریافت شد.');
      return answer;
    } on Exception {
      rethrow;
    } catch (_) {
      throw Exception('اتصال اینترنت یا سرویس هوش مصنوعی در دسترس نیست.');
    }
  }

  void dispose() => client.close();
}
