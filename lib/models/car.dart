/// مدل کامل خودرو
class Car {
  // ── شناسه ──
  final String id;

  // ── مشخصات اصلی ──
  final String brand;
  final String model;

  /// سال نمونه در لیست (اختیاری) — سال واقعی را کاربر جدا وارد می‌کند
  final String year;
  final String engine;

  // ── مشخصات اضافه ──
  final String? region;
  final FuelType? fuelType;               // ✅ تغییر به Enum
  final TransmissionType? transmission;  // ✅ تغییر به Enum
  final CarCategory? category;            // ✅ تغییر به Enum
  final String? imageUrl;       
  final String? countryOfOrigin; 

  // ── ویژگی‌های بولی ──
  final bool isPopular;         
  final bool isElectric;        
  final bool isActive;          

  /// نام‌های جایگزین برای جستجو (مثلاً ال۹۰، L90)
  final List<String> aliases;

  // ── مشکلات و تاریخچه ──
  final List<String> commonIssues;
  final List<CarHistoryEntry> history;

  // ── اطلاعات تکمیلی ──
  final int? productionStartYear;  
  final int? productionEndYear;    

  const Car({
    required this.id,
    required this.brand,
    required this.model,
    this.year = '',
    required this.engine,
    this.region,
    this.fuelType,
    this.transmission,
    this.category,
    this.imageUrl,
    this.countryOfOrigin,
    this.isPopular = false,
    this.isElectric = false,
    this.isActive = true,
    this.aliases = const [],
    this.commonIssues = const [],
    this.history = const [],
    this.productionStartYear,
    this.productionEndYear,
  });

  // ─────────────────────────────────────────
  // ── سازنده از JSON ──
  // ─────────────────────────────────────────
  factory Car.fromJson(Map<String, dynamic> json) {
    return Car(
      id: _str(json['id']),
      brand: _str(json['brand']),
      model: _str(json['model']),
      year: json['year']?.toString() ?? '',
      engine: _str(json['engine']),
      region: json['region']?.toString(),
      // ✅ استفاده از متدهای ایمن تبدیل استرینگ به Enum
      fuelType: FuelType.fromString(json['fuelType']?.toString()),
      transmission: TransmissionType.fromString((json['transmission'] ?? json['gearbox'])?.toString()),
      category: CarCategory.fromString(json['category']?.toString()),
      imageUrl: (json['imageUrl'] ?? json['image_url'])?.toString(),
      countryOfOrigin: (json['countryOfOrigin'] ?? json['country_of_origin'])?.toString(),
      isPopular: _bool(json['isPopular'] ?? json['is_popular']),
      isElectric: _bool(json['isElectric'] ?? json['is_electric']),
      isActive: _bool(json['isActive'] ?? json['is_active'], defaultValue: true),
      aliases: _parseStringList(json['aliases']),
      commonIssues: _parseStringList(json['commonIssues']),
      history: _parseHistory(json['history']),
      productionStartYear: _parseInt(json['productionStartYear']),
      productionEndYear: _parseInt(json['productionEndYear']),
    );
  }

  // ─────────────────────────────────────────
  // ── تبدیل به JSON ──
  // ─────────────────────────────────────────
  Map<String, dynamic> toJson() => {
        'id': id,
        'brand': brand,
        'model': model,
        'year': year,
        'engine': engine,
        if (region != null) 'region': region,
        // ✅ سریالایز کردن نام Enum به جای استرینگ خام
        if (fuelType != null) 'fuelType': fuelType!.name,
        if (transmission != null) 'transmission': transmission!.name,
        if (category != null) 'category': category!.name,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (countryOfOrigin != null) 'countryOfOrigin': countryOfOrigin,
        'isPopular': isPopular,
        'isElectric': isElectric,
        'isActive': isActive,
        if (aliases.isNotEmpty) 'aliases': aliases,
        'commonIssues': commonIssues,
        'history': history.map((h) => h.toJson()).toList(),
        if (productionStartYear != null)
          'productionStartYear': productionStartYear,
        if (productionEndYear != null) 'productionEndYear': productionEndYear,
      };

  // ─────────────────────────────────────────
  // ── copyWith ──
  // ─────────────────────────────────────────
  Car copyWith({
    String? id,
    String? brand,
    String? model,
    String? year,
    String? engine,
    String? region,
    FuelType? fuelType,
    TransmissionType? transmission,
    CarCategory? category,
    String? imageUrl,
    String? countryOfOrigin,
    bool? isPopular,
    bool? isElectric,
    bool? isActive,
    List<String>? aliases,
    List<String>? commonIssues,
    List<CarHistoryEntry>? history,
    int? productionStartYear,
    int? productionEndYear,
  }) {
    return Car(
      id: id ?? this.id,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      year: year ?? this.year,
      engine: engine ?? this.engine,
      region: region ?? this.region,
      fuelType: fuelType ?? this.fuelType,
      transmission: transmission ?? this.transmission,
      category: category ?? this.category,
      imageUrl: imageUrl ?? this.imageUrl,
      countryOfOrigin: countryOfOrigin ?? this.countryOfOrigin,
      isPopular: isPopular ?? this.isPopular,
      isElectric: isElectric ?? this.isElectric,
      isActive: isActive ?? this.isActive,
      aliases: aliases ?? this.aliases,
      commonIssues: commonIssues ?? this.commonIssues,
      history: history ?? this.history,
      productionStartYear: productionStartYear ?? this.productionStartYear,
      productionEndYear: productionEndYear ?? this.productionEndYear,
    );
  }

  // ─────────────────────────────────────────
  // ── Getters محاسباتی ──
  // ─────────────────────────────────────────

  /// نام کامل بدون سال — برای نمایش در UI
  String get fullName {
    final b = brand.trim();
    final m = model.trim();
    if (b.isEmpty && m.isEmpty) return 'خودروی ناشناس';
    if (b.isEmpty) return m;
    if (m.isEmpty) return b;
    return '$b $m';
  }

  /// نام کامل با سال (اگر سال موجود باشد)
  String get fullNameWithYear {
    if (year.isEmpty) return fullName;
    return '$fullName ($year)';
  }

  /// توضیح کوتاه برای زیرعنوان
  String get description {
    final parts = <String>[];
    if (category != null) parts.add(category!.label);
    if (engine.isNotEmpty) parts.add(engine);
    if (fuelType != null) parts.add(fuelType!.label);
    if (transmission != null) parts.add(transmission!.label);
    if (isElectric) parts.add('⚡ برقی');
    return parts.join(' · ');
  }

  /// متن یکپارچه برای جستجو (شامل نام‌های جایگزین و ارقام فارسی)
  String get searchBlob {
    final parts = <String>[
      fullName,
      brand,
      model,
      engine,
      year,
      ...aliases,
      if (fuelType != null) fuelType!.label,
      if (transmission != null) transmission!.label,
      if (category != null) ...[category!.label, ...category!.searchAliases],
      if (region != null) region!,
      if (countryOfOrigin != null) countryOfOrigin!,
    ];
    return parts.join(' ');
  }

  bool matchesQuery(String query) {
    final q = normalizeSearch(query.trim());
    if (q.isEmpty) return true;
    return normalizeSearch(searchBlob).contains(q);
  }

  /// یکسان‌سازی ارقام فارسی/عربی و حروف عربی برای جستجو
  static String normalizeSearch(String input) {
    var s = input.toLowerCase();
    const map = <String, String>{
      '۰': '0',
      '۱': '1',
      '۲': '2',
      '۳': '3',
      '۴': '4',
      '۵': '5',
      '۶': '6',
      '۷': '7',
      '۸': '8',
      '۹': '9',
      '٠': '0',
      '١': '1',
      '٢': '2',
      '٣': '3',
      '٤': '4',
      '٥': '5',
      '٦': '6',
      '٧': '7',
      '٨': '8',
      '٩': '9',
      'ي': 'ی',
      'ى': 'ی',
      'ك': 'ک',
    };
    map.forEach((from, to) {
      s = s.replaceAll(from, to);
    });
    return s.replaceAll('\u200c', '');
  }

  /// آیا در حال تولید است
  bool get isInProduction => productionEndYear == null && isActive;

  /// بازه تولید برای نمایش
  String get productionRange {
    if (productionStartYear == null) return '';
    final end = productionEndYear?.toString() ?? 'تاکنون';
    return '$productionStartYear - $end';
  }

  /// آیا تصویر دارد
  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  // ─────────────────────────────────────────
  // ── مقایسه ──
  // ─────────────────────────────────────────

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Car && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'Car(id=$id, name=$fullName, engine=$engine, isPopular=$isPopular)';

  // ─────────────────────────────────────────
  // ── توابع کمکی private ──
  // ─────────────────────────────────────────

  static String _str(dynamic value) =>
      value == null ? '' : value.toString().trim();

  static bool _bool(dynamic value, {bool defaultValue = false}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) return value == 'true' || value == '1';
    return defaultValue;
  }

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static List<String> _parseStringList(dynamic raw) {
    if (raw is List) {
      return raw
          .map((e) => e?.toString().trim() ?? '')
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (raw is String && raw.isNotEmpty) return [raw.trim()];
    return [];
  }

  static List<CarHistoryEntry> _parseHistory(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(CarHistoryEntry.fromJson)
        .toList();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ── مدل تاریخچه خودرو ──
// ─────────────────────────────────────────────────────────────────────────────
class CarHistoryEntry {
  final String id;
  final String title;
  final String? description;
  final DateTime? date;
  final String? type; // 'repair', 'recall', 'update', ...

  const CarHistoryEntry({
    required this.id,
    required this.title,
    this.description,
    this.date,
    this.type,
  });

  factory CarHistoryEntry.fromJson(Map<String, dynamic> json) {
    // ✅ استفاده از tryParse به جای try-catch
    final dateStr = json['date']?.toString();
    final date = dateStr != null ? DateTime.tryParse(dateStr) : null;

    return CarHistoryEntry(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: json['description']?.toString(),
      date: date,
      type: json['type']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (description != null) 'description': description,
        if (date != null) 'date': date!.toIso8601String(),
        if (type != null) 'type': type,
      };

  @override
  String toString() => 'CarHistoryEntry(id=$id, title=$title, type=$type)';
}

// ─────────────────────────────────────────────────────────────────────────────
// ── دسته‌بندی خودرو ──
// ─────────────────────────────────────────────────────────────────────────────
enum CarCategory {
  sedan,
  suv,
  hatchback,
  pickup,
  van,
  coupe,
  convertible,
  wagon,
  motorcycle,
  scooter,
  atv,
  truck,
  bus,
  minibus,
  tractor,
  heavy,
  other;

  String get label => switch (this) {
        CarCategory.sedan => 'سدان',
        CarCategory.suv => 'شاسی‌بلند',
        CarCategory.hatchback => 'هاچ‌بک',
        CarCategory.pickup => 'وانت',
        CarCategory.van => 'ون',
        CarCategory.coupe => 'کوپه',
        CarCategory.convertible => 'کابریولت',
        CarCategory.wagon => 'واگن',
        CarCategory.motorcycle => 'موتورسیکلت',
        CarCategory.scooter => 'اسکوتر',
        CarCategory.atv => 'چهارچرخ',
        CarCategory.truck => 'کامیون',
        CarCategory.bus => 'اتوبوس',
        CarCategory.minibus => 'مینی‌بوس',
        CarCategory.tractor => 'تراکتور',
        CarCategory.heavy => 'ماشین‌آلات سنگین',
        CarCategory.other => 'سایر',
      };

  /// نام‌های متداول برای جستجو
  List<String> get searchAliases => switch (this) {
        CarCategory.motorcycle => const ['موتور', 'موتور سیکلت', 'bike', 'moto'],
        CarCategory.scooter => const ['اسکوتر', 'موتور برقی'],
        CarCategory.atv => const ['ATV', 'کواد', 'چهار چرخ'],
        CarCategory.truck => const ['کامیون', 'خاور', 'تریلی', 'کشنده'],
        CarCategory.bus => const ['اتوبوس'],
        CarCategory.minibus => const ['مینی بوس', 'مینیبوس'],
        CarCategory.tractor => const ['تراکتور', 'کشاورزی'],
        CarCategory.heavy => const [
            'ماشین آلات',
            'بیل مکانیکی',
            'لودر',
            'گریدر',
            'غلطک',
            'جرثقیل',
            'راه‌سازی',
          ],
        CarCategory.pickup => const ['پیکاپ', 'وانت'],
        CarCategory.suv => const ['شاسی بلند', 'کراس‌اوور', 'کراس اوور'],
        _ => const [],
      };

  /// پارس از رشته JSON (ایمن و بدون Exception)
  static CarCategory? fromString(String? value) {
    if (value == null || value.isEmpty) return null;
    final lower = value.toLowerCase().trim();
    for (final cat in CarCategory.values) {
      if (cat.name == lower) return cat;
    }
    const aliases = <String, CarCategory>{
      'سدان': CarCategory.sedan,
      'sedan': CarCategory.sedan,
      'شاسی‌بلند': CarCategory.suv,
      'شاسی بلند': CarCategory.suv,
      'suv': CarCategory.suv,
      'crossover': CarCategory.suv,
      'هاچ‌بک': CarCategory.hatchback,
      'هاچبک': CarCategory.hatchback,
      'hatchback': CarCategory.hatchback,
      'وانت': CarCategory.pickup,
      'پیکاپ': CarCategory.pickup,
      'pickup': CarCategory.pickup,
      'ون': CarCategory.van,
      'van': CarCategory.van,
      'کوپه': CarCategory.coupe,
      'coupe': CarCategory.coupe,
      'کابریولت': CarCategory.convertible,
      'convertible': CarCategory.convertible,
      'واگن': CarCategory.wagon,
      'wagon': CarCategory.wagon,
      'موتورسیکلت': CarCategory.motorcycle,
      'موتور': CarCategory.motorcycle,
      'motorcycle': CarCategory.motorcycle,
      'bike': CarCategory.motorcycle,
      'اسکوتر': CarCategory.scooter,
      'scooter': CarCategory.scooter,
      'چهارچرخ': CarCategory.atv,
      'atv': CarCategory.atv,
      'quad': CarCategory.atv,
      'کامیون': CarCategory.truck,
      'truck': CarCategory.truck,
      'اتوبوس': CarCategory.bus,
      'bus': CarCategory.bus,
      'مینی‌بوس': CarCategory.minibus,
      'مینی بوس': CarCategory.minibus,
      'minibus': CarCategory.minibus,
      'تراکتور': CarCategory.tractor,
      'tractor': CarCategory.tractor,
      'ماشین‌آلات سنگین': CarCategory.heavy,
      'ماشین آلات سنگین': CarCategory.heavy,
      'heavy': CarCategory.heavy,
      'construction': CarCategory.heavy,
    };
    return aliases[lower] ?? CarCategory.other;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ── نوع سوخت ──
// ─────────────────────────────────────────────────────────────────────────────
enum FuelType {
  gasoline,
  diesel,
  cng,
  electric,
  hybrid,
  lpg;

  String get label => switch (this) {
        FuelType.gasoline => 'بنزینی',
        FuelType.diesel => 'دیزل',
        FuelType.cng => 'گاز سوز',
        FuelType.electric => 'برقی',
        FuelType.hybrid => 'هیبریدی',
        FuelType.lpg => 'گاز مایع',
      };

  static FuelType? fromString(String? value) {
    if (value == null || value.isEmpty) return null;
    final lower = value.toLowerCase().trim();
    for (final type in FuelType.values) {
      if (type.name == lower) return type;
    }
    const aliases = <String, FuelType>{
      'petrol': FuelType.gasoline,
      'بنزین': FuelType.gasoline,
      'بنزینی': FuelType.gasoline,
      'گازوئیل': FuelType.diesel,
      'دیزلی': FuelType.diesel,
      'diesel': FuelType.diesel,
      'دوگانه': FuelType.cng,
      'گازسوز': FuelType.cng,
      'گاز سوز': FuelType.cng,
      'cng': FuelType.cng,
      'برقی': FuelType.electric,
      'ev': FuelType.electric,
      'هیبرید': FuelType.hybrid,
      'هیبریدی': FuelType.hybrid,
      'phev': FuelType.hybrid,
      'گاز مایع': FuelType.lpg,
    };
    return aliases[lower];
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ── نوع گیربکس ──
// ─────────────────────────────────────────────────────────────────────────────
enum TransmissionType {
  manual,
  automatic,
  cvt,
  dct;

  String get label => switch (this) {
        TransmissionType.manual => 'دستی',
        TransmissionType.automatic => 'اتوماتیک',
        TransmissionType.cvt => 'CVT',
        TransmissionType.dct => 'دوکلاچه',
      };

  static TransmissionType? fromString(String? value) {
    if (value == null || value.isEmpty) return null;
    final lower = value.toLowerCase().trim();
    for (final type in TransmissionType.values) {
      if (type.name == lower) return type;
    }
    const aliases = <String, TransmissionType>{
      'دستی': TransmissionType.manual,
      'مانوال': TransmissionType.manual,
      'manual': TransmissionType.manual,
      'اتومات': TransmissionType.automatic,
      'اتوماتیک': TransmissionType.automatic,
      'automatic': TransmissionType.automatic,
      'اتوماتیک cvt': TransmissionType.cvt,
    };
    return aliases[lower];
  }
}
