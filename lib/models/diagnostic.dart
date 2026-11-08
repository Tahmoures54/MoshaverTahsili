import '../constants.dart';
import 'car.dart';

/// مدل کامل عیب‌یابی
class Diagnostic {
  // ── شناسه‌ها ──
  final String id;
  final String carId;
  final String? carName;    // نام خودرو در زمان عیب‌یابی
  final String? carYear;   // سال خودرو در زمان عیب‌یابی
  final Car? car;           // آبجکت کامل خودرو (اگر سرور populate کرده باشد)

  // ── زمان‌ها ──
  final DateTime createdAt;   // زمان ایجاد
  final DateTime? updatedAt;  // آخرین آپدیت

  // ── محتوا ──
  final String? description;     // توضیح کاربر
  final String? result;          // پاسخ AI

  // ── امتیازها ──
  final double? confidenceScore; // اطمینان AI
  final int? userRating;         // امتیاز کاربر (1-5)

  // ── وضعیت ──
  final DiagnosticStatus status;
  final DiagnosticType type;      // پیام متنی
  final bool isGolden;            // آیا با اشتراک طلایی انجام شده

  // ── اطلاعات اضافی ──
  final String? errorMessage;     
  final Map<String, dynamic>? metadata; 

  const Diagnostic({
    required this.id,
    required this.carId,
    required this.createdAt,
    this.carName,
    this.carYear,
    this.car,
    this.updatedAt,
    this.description,
    this.result,
    this.confidenceScore,
    this.userRating,
    this.status = DiagnosticStatus.completed,
    this.type = DiagnosticType.text,
    this.isGolden = false,
    this.errorMessage,
    this.metadata,
  });

  // ─────────────────────────────────────────
  // ── سازنده از JSON ──
  // ─────────────────────────────────────────
  factory Diagnostic.fromJson(Map<String, dynamic> json) {
    // ── پارس تاریخ‌ها (پشتیبانی از استرینگ و Unix Timestamp) ──
    final createdAt = _parseDate(json['createdAt'] ?? json['created_at'] ?? json['timestamp']) ?? DateTime.now();
    final updatedAt = _parseDate(json['updatedAt'] ?? json['updated_at']);

    // ── پارس Car ──
    final Car? car = json['car'] is Map<String, dynamic>
        ? Car.fromJson(json['car'] as Map<String, dynamic>)
        : null;

    // ── پارس metadata (ایمن در برابر خطای نوع) ──
    final Map<String, dynamic>? metadata = json['metadata'] is Map
        ? Map<String, dynamic>.from(json['metadata'] as Map)
        : null;

    return Diagnostic(
      id: _str(json['id']),
      carId: _str(json['carId'] ?? json['car_id']),
      // ✅ استفاده از ?.toString() برای جلوگیری از کرش
      carName: (json['carName'] ?? json['car_name'])?.toString(),
      carYear: (json['carYear'] ?? json['car_year'])?.toString(),
      car: car,
      createdAt: createdAt,
      updatedAt: updatedAt,
      // دستور سیاست «پاسخ مستقیم» بخشی از متنِ ذخیره‌شده در بک‌اند است؛
      // هنگام نمایش (تاریخچه/جست‌وجو) همیشه از متن پاک‌شده استفاده می‌کنیم.
      description: _cleanDescription(json['description']),
      result: json['result']?.toString(),
      confidenceScore: _parseDouble(json['confidenceScore'] ?? json['confidence_score']),
      userRating: _parseInt(json['userRating'] ?? json['user_rating']),
      status: DiagnosticStatus.fromString(json['status']?.toString()),
      type: DiagnosticType.fromString(json['type']?.toString()),
      isGolden: _bool(json['isGolden'] ?? json['is_golden']),
      errorMessage: (json['errorMessage'] ?? json['error_message'])?.toString(),
      metadata: metadata,
    );
  }

  // ─────────────────────────────────────────
  // ── تبدیل به JSON ──
  // ─────────────────────────────────────────
  Map<String, dynamic> toJson() => {
        'id': id,
        'carId': carId,
        if (carName != null) 'carName': carName,
        if (carYear != null) 'carYear': carYear,
        if (car != null) 'car': car!.toJson(),
        'createdAt': createdAt.toIso8601String(),
        if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
        if (description != null) 'description': description,
        if (result != null) 'result': result,
        if (confidenceScore != null) 'confidenceScore': confidenceScore,
        if (userRating != null) 'userRating': userRating,
        'status': status.name,
        'type': type.name,
        'isGolden': isGolden,
        if (errorMessage != null) 'errorMessage': errorMessage,
        if (metadata != null) 'metadata': metadata,
      };

  // ─────────────────────────────────────────
  // ── copyWith ──
  // ─────────────────────────────────────────
  Diagnostic copyWith({
    String? id,
    String? carId,
    String? carName,
    String? carYear,
    Car? car,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? description,
    String? result,
    double? confidenceScore,
    int? userRating,
    DiagnosticStatus? status,
    DiagnosticType? type,
    bool? isGolden,
    String? errorMessage,
    Map<String, dynamic>? metadata,
  }) {
    return Diagnostic(
      id: id ?? this.id,
      carId: carId ?? this.carId,
      carName: carName ?? this.carName,
      carYear: carYear ?? this.carYear,
      car: car ?? this.car,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      description: description ?? this.description,
      result: result ?? this.result,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      userRating: userRating ?? this.userRating,
      status: status ?? this.status,
      type: type ?? this.type,
      isGolden: isGolden ?? this.isGolden,
      errorMessage: errorMessage ?? this.errorMessage,
      metadata: metadata ?? this.metadata,
    );
  }

  // ─────────────────────────────────────────
  // ── Getters محاسباتی ──
  // ─────────────────────────────────────────

  String get displayCarName {
    if (carName != null && carName!.isNotEmpty) return carName!;
    if (car != null) return car!.fullName;
    if (carId.isNotEmpty) return carId;
    return 'خودروی ناشناس';
  }

  String get displayCarNameWithYear {
    final name = displayCarName;
    if (carYear != null && carYear!.isNotEmpty) return '$name ($carYear)';
    return name;
  }

  String get summary {
    String? text = description;
    if (text == null || text.isEmpty) text = result;
    
    if (text != null && text.isNotEmpty) {
      return text.length > 80 ? '${text.substring(0, 80)}...' : text;
    }
    return 'بدون توضیحات';
  }

  String get fullContent => result ?? description ?? 'بدون محتوا';
  bool get hasResult => result != null && result!.isNotEmpty;
  bool get isRated => userRating != null;
  bool get isSuccessful => status == DiagnosticStatus.completed && hasResult;
  bool get isPending => status == DiagnosticStatus.pending;
  bool get hasFailed => status == DiagnosticStatus.failed;

  String get formattedDate {
    final d = createdAt;
    final date = '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
    final time = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '$date  $time';
  }

  String get confidencePercent {
    if (confidenceScore == null) return '';
    return '${(confidenceScore! * 100).toStringAsFixed(0)}٪';
  }

  // ─────────────────────────────────────────
  // ── مقایسه ──
  // ─────────────────────────────────────────
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Diagnostic && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Diagnostic(id=$id, car=$displayCarName, status=${status.name}, type=${type.name})';

  // ─────────────────────────────────────────
  // ── توابع کمکی private ──
  // ─────────────────────────────────────────
  static String _str(dynamic value) => value == null ? '' : value.toString().trim();

  // ✅ پشتیبانی از Timestamp عددی (Unix) برای تاریخ‌ها
  static DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }
    return null;
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// توضیحِ پاک‌شده از دستور داخلی سیاست پاسخ — فقط برای نمایش.
  static String? _cleanDescription(dynamic value) {
    if (value == null) return null;
    final raw = value.toString();
    if (raw.trim().isEmpty) return null;
    return DiagnosisPolicy.stripDirective(raw);
  }

  static bool _bool(dynamic value, {bool defaultValue = false}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) return value == 'true' || value == '1';
    return defaultValue;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ── وضعیت عیب‌یابی ──
// ─────────────────────────────────────────────────────────────────────────────
enum DiagnosticStatus {
  pending,
  processing,
  completed,
  failed;

  String get label => switch (this) {
        DiagnosticStatus.pending => 'در انتظار',
        DiagnosticStatus.processing => 'در حال پردازش',
        DiagnosticStatus.completed => 'انجام‌شده',
        DiagnosticStatus.failed => 'ناموفق',
      };

  // ✅ استفاده از حلقه for برای ایمنی و پرفورمنس بهتر
  static DiagnosticStatus fromString(String? value) {
    if (value == null) return DiagnosticStatus.completed;
    final lower = value.toLowerCase();
    for (final status in DiagnosticStatus.values) {
      if (status.name == lower) return status;
    }
    return DiagnosticStatus.completed;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ── نوع عیب‌یابی ──
// ─────────────────────────────────────────────────────────────────────────────
enum DiagnosticType {
  text;

  String get label => '💬 متنی';

  static DiagnosticType fromString(String? value) => DiagnosticType.text;
}
