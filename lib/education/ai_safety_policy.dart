/// A small offline preflight for explicit self-harm intent.
/// This is a conservative keyword/rule screen, NOT a clinical risk assessment
/// and it cannot reliably detect every crisis or euphemism.
enum AiSafetyDisposition { allow, urgentHumanSupport }

class AiSafetyResult {
  const AiSafetyResult(this.disposition, {this.localResponse});
  final AiSafetyDisposition disposition;
  final String? localResponse;
  bool get shouldBlockRemoteAi => disposition != AiSafetyDisposition.allow;
}

class AiSafetyPolicy {
  AiSafetyPolicy._();

  static final RegExp _explicitIntent = RegExp(
    r'(?:می\s*خوام|می\s*خواهم|قصد\s*دارم|تصمیم\s*دارم|کاش)\s*.{0,35}(?:خودکشی\s*کنم|خودم\s*را\s*بکشم|خودمو\s*بکشم|به\s*خودم\s*(?:آسیب|صدمه)\s*بزنم|به\s*زندگی\s*ام\s*پایان|بمیرم)|'
    r'(?:دیگه\s*نمی\s*خوام\s*زنده\s*باشم|نمی\s*خوام\s*زنده\s*بمونم|کاش\s*مرده\s*بودم)|'
    r'\b(?:i\s*want\s*to\s*die|want\s*to\s*kill\s*myself|kill\s*myself|end\s*my\s*life|hurt\s*myself|self[- ]harm)\b',
    caseSensitive: false,
  );

  static AiSafetyResult assess(String message) {
    final normalized = message
        .replaceAll('ي', 'ی')
        .replaceAll('ك', 'ک')
        .replaceAll('ـ', '')
        .replaceAll(RegExp(r'[\u200c\u200f\u202a-\u202e]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
    if (!_explicitIntent.hasMatch(normalized)) {
      return const AiSafetyResult(AiSafetyDisposition.allow);
    }
    return const AiSafetyResult(
      AiSafetyDisposition.urgentHumanSupport,
      localResponse: 'ممنونم که این موضوع را گفتی. لازم نیست در این لحظه با این احساس تنها بمانی. این پاسخ محلی سیمرغ است و پیام تو به سرویس هوش مصنوعی ارسال نشد. اگر احتمال می‌دهی همین حالا به خودت آسیب بزنی، لطفاً تنها نمان، از داروها یا وسایل خطرناک فاصله بگیر و همین حالا به یک بزرگسال قابل اعتماد که نزدیکت است خبر بده و از خدمات اضطراری محل زندگی کمک فوری بگیر. اگر خطر فوری نیست هم امروز با والد یا سرپرست امن، مشاور مدرسه یا متخصص سلامت روان صحبت کن. من جای کمک انسانی و تخصصی را نمی‌گیرم.',
    );
  }
}
