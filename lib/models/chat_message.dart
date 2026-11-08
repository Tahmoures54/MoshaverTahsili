import 'diagnosis_result.dart';

enum MessageRole { user, assistant, system }

class ChatMessage {
  final String id;
  final String text;
  final MessageRole role;
  final DateTime timestamp;
  final bool isDiagnosisResult;
  final DiagnosisResult? structured;

  /// وقتی این پیام یک خطاست، متن اصلی کاربر که باعث خطا شد اینجاست
  /// تا دکمهٔ «تلاش دوباره» بتواند همان درخواست را از نو بفرستد.
  final String? retryText;

  /// شناسهٔ همان درخواست تشخیص برای retry امن پس از timeout/network error.
  final String? retryRequestId;

  /// نوع خطا برای تعیین رفتار UI (مثلاً باز کردن فروشگاه برای 402).
  final ChatErrorType? errorType;

  ChatMessage({
    required this.id,
    required this.text,
    required this.role,
    DateTime? timestamp,
    this.isDiagnosisResult = false,
    this.structured,
    this.retryText,
    this.retryRequestId,
    this.errorType,
  }) : timestamp = timestamp ?? DateTime.now();

  static int _seq = 0;
  static String _nextId(String prefix) => '${prefix}_${_seq++}_${DateTime.now().microsecondsSinceEpoch}';

  factory ChatMessage.user(String text) => ChatMessage(
        id: _nextId('u'),
        text: text,
        role: MessageRole.user,
      );

  factory ChatMessage.assistant(
    String text, {
    bool isDiagnosisResult = false,
    DiagnosisResult? structured,
  }) =>
      ChatMessage(
        id: _nextId('a'),
        text: text,
        role: MessageRole.assistant,
        isDiagnosisResult: isDiagnosisResult,
        structured: structured,
      );

  factory ChatMessage.error(
    String text, {
    String? retryText,
    String? retryRequestId,
    ChatErrorType? errorType,
  }) => ChatMessage(
        id: _nextId('e'),
        text: text,
        role: MessageRole.system,
        retryText: retryText,
        retryRequestId: retryRequestId,
        errorType: errorType,
      );
}

enum ChatErrorType {
  generic,
  unauthorized,
  insufficientCredits,
  server,
  network,
}

