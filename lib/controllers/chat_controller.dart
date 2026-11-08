import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import '../models/diagnosis_result.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';

/// منطق کسب‌وکار صفحهٔ چت، کاملاً جدا از UI — قابل تست بدون WidgetTester.
///
/// UI فقط این کنترلر را listen می‌کند و روی رویداد onMessageAppended
/// (اسکرول/لرزش) واکنش نشان می‌دهد.
class ChatController extends ChangeNotifier {
  ChatController({
    required this.carId,
    required this.carName,
    required this.year,
    required this.isCustomCar,
    required this.apiService,
    required this.authProvider,
    this.onMessageAppended,
    this.latitude,
    this.longitude,
  });

  final String carId;
  final String carName;
  final String year;
  final bool isCustomCar;
  final ApiService apiService;
  final AuthProvider authProvider;
  double? latitude;
  double? longitude;

  /// مختصات آخرین موقعیت شناخته‌شدهٔ کاربر برای مرتب‌سازی تبلیغ‌های چت.
  /// در صورت نبودن اجازه یا موقعیت، backend همچنان فقط تعمیرگاه‌های approved را برمی‌گرداند.
  void setLocation({double? lat, double? lng}) {
    latitude = lat;
    longitude = lng;
  }

  /// (index, isDiagnosisResult) — UI از این برای تصمیم «اسکرول ساده» یا
  /// «اسکرول به نتیجه + لرزش» استفاده می‌کند.
  final void Function(int index, bool isDiagnosisResult)? onMessageAppended;

  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  // مکالمهٔ واقعی برای ارسال به مدل؛ پیام‌های خطا و پیام خوشامد UI وارد آن نمی‌شوند.
  final List<Map<String, String>> _conversationHistory = [];
  List<Map<String, String>> get conversationHistory => _conversationHistory
      .map((message) => Map<String, String>.unmodifiable(message))
      .toList(growable: false);

  bool _isTyping = false;
  bool get isTyping => _isTyping;

  String? _lastDiagnosticId;
  bool _disposed = false;
  static int _requestSequence = 0;

  String _newRequestId() =>
      'diag_${DateTime.now().microsecondsSinceEpoch}_${_requestSequence++}';

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  void seedInitial({
    required String userMessage,
    String? initialResultText,
    Map<String, dynamic>? initialResultJson,
    String? initialDiagnosticId,
  }) {
    _conversationHistory.add({'role': 'user', 'content': userMessage.trim()});
    _append(ChatMessage.assistant(
      'سلام! دارم مشکل «$carName» مدل $year را بررسی می‌کنم.\nمشکل: $userMessage',
    ));

    if (initialResultText != null && initialResultText.trim().isNotEmpty) {
      _lastDiagnosticId = initialDiagnosticId;
      _conversationHistory.add({'role': 'assistant', 'content': initialResultText.trim()});
      _appendDiagnosisResult(initialResultText, initialResultJson);
      // عیب‌یابی اولیه (مثلاً تحلیل صوتی) سهمیه را سمت سرور کم کرده است؛
      // نشان اعتبار در AppBar نباید کهنه بماند.
      unawaited(authProvider.fetchProfile());
    } else {
      unawaited(fetchDiagnosis(userMessage, requestId: _newRequestId()));
    }
  }

  /// سیاست «پاسخ مستقیم»: کاربر همیشه آزاد است هر متنی بنویسد و بفرستد؛
  /// هیچ حالت قفل‌شدهٔ «منتظر انتخاب گزینه‌ها» وجود ندارد. کارت تشخیص
  /// هرگز ورودی آزاد را غیرفعال نمی‌کند.
  Future<void> sendUserMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isTyping) return;

    _append(ChatMessage.user(trimmed));
    _conversationHistory.add({'role': 'user', 'content': trimmed});
    await fetchDiagnosis(trimmed, requestId: _newRequestId());
  }

  /// تلاش دوباره روی یک پیام خطا؛ پیام خطا از لیست حذف می‌شود و درخواست
  /// با همان متن اصلی کاربر دوباره ارسال می‌شود.
  Future<void> retry(ChatMessage errorMessage) async {
    if (errorMessage.retryText == null || _isTyping) return;
    _messages.remove(errorMessage);
    _safeNotify();
    // درخواست ناموفق را به انتهای تاریخچه برمی‌گردانیم تا retry همان سؤال را
    // با زمینهٔ درست ارسال کند و متن کاربر دوبار تکرار نشود.
    final retryText = errorMessage.retryText!;
    final previousUserIndex = _conversationHistory.lastIndexWhere(
      (entry) => entry['role'] == 'user' && entry['content'] == retryText,
    );
    if (previousUserIndex >= 0) _conversationHistory.removeAt(previousUserIndex);
    _conversationHistory.add({'role': 'user', 'content': retryText});
    await fetchDiagnosis(
      retryText,
      requestId: errorMessage.retryRequestId ?? _newRequestId(),
    );
  }

  Future<void> fetchDiagnosis(String description, {required String requestId}) async {
    _isTyping = true;
    _safeNotify();

    try {
      final token = authProvider.token;
      if (token == null || token.isEmpty) {
        throw const ApiException(401, 'لطفاً دوباره وارد شوید.');
      }

      final response = await apiService.diagnoseDetailed(
        token,
        carId,
        description,
        year: year,
        carName: isCustomCar ? carName : null,
        previousDiagnosticId: _lastDiagnosticId,
        conversationHistory: conversationHistory,
        requestId: requestId,
        lat: latitude,
        lng: longitude,
      );

      if (_disposed) return;

      _lastDiagnosticId = response.diagnosticId;
      unawaited(authProvider.fetchProfile());

      // فرض: ApiService به‌مرور فیلد اختیاری `structured` (Map<String,dynamic>؟)
      // را هم برمی‌گرداند (خروجی خام DiagnosisResponseSchema). تا وقتی بک‌اند
      // به‌روزرسانی نشده، این فیلد null است و UI به‌صورت متن ساده fallback می‌کند.
      final structuredJson = response.structured;
      _conversationHistory.add({'role': 'assistant', 'content': response.result});
      _appendDiagnosisResult(response.result, structuredJson);
    } on ApiException catch (e) {
      if (_disposed) return;
      _append(ChatMessage.error(
        _messageForApiError(e),
        retryText: e.statusCode == 402 ? null : description,
        retryRequestId: e.statusCode == 402 ? null : requestId,
        errorType: _errorTypeFor(e),
      ));
    } catch (_) {
      if (_disposed) return;
      _append(ChatMessage.error(
        'خطا در عیب‌یابی. لطفاً دوباره تلاش کنید.',
        retryText: description,
        retryRequestId: requestId,
      ));
    } finally {
      if (!_disposed) {
        _isTyping = false;
        _safeNotify();
      }
    }
  }

  void _appendDiagnosisResult(String text, Map<String, dynamic>? json) {
    final structured = DiagnosisResult.tryParse(json);
    _append(ChatMessage.assistant(text, isDiagnosisResult: true, structured: structured));
  }

  void _append(ChatMessage message) {
    _messages.add(message);
    _safeNotify();
    onMessageAppended?.call(_messages.length - 1, message.isDiagnosisResult);
  }

  ChatErrorType _errorTypeFor(ApiException e) {
    if (e.statusCode == 401) return ChatErrorType.unauthorized;
    if (e.statusCode == 402) return ChatErrorType.insufficientCredits;
    if (e.statusCode >= 500) return ChatErrorType.server;
    if (e.statusCode == 0 || e.statusCode == 408) return ChatErrorType.network;
    return ChatErrorType.generic;
  }

  String _messageForApiError(ApiException e) {
    switch (e.statusCode) {
      case 402:
        return 'اعتبار شما کافی نیست. لطفاً از فروشگاه بسته بخرید.';
      case 401:
        return 'نشست شما منقضی شده است. لطفاً دوباره وارد شوید.';
      default:
        return e.message;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
