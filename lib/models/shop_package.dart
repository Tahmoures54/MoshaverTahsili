/// مدل بسته‌های فروشگاهی نسخه موبایل؛ شناسه‌ها باید با محصولات بازار یکی باشند.
///
/// سیاست نسخه بازار: اعتبارها در دفتر محلی ثبت می‌شوند و هر عیب‌یابی موفق
/// پس از دو مورد رایگان یک اعتبار کم می‌کند. جدول محصولات در PRICING.md است.
///
/// ─── سیاست قیمت‌گذاری (نسخهٔ بازار) ───
/// • قیمت ارزان‌ترین بسته ۴۹٬۰۰۰ تومان است.
/// • بسته‌های بزرگ‌تر، به‌ازای هر عیب‌یابی ارزان‌تر می‌شوند.
/// • همه بسته‌ها اعتبار کل مشخص دارند و محدودیت روزانه ندارند.
/// • پس از دو عیب‌یابی رایگان، هر عیب‌یابی موفق یک اعتبار کم می‌کند.
class ShopPackage {
  final String id;
  final String title;
  final String subtitle;
  final int priceToman;
  final int? compareAtPriceToman;
  final int? credits;
  final int? days;

  /// فیلد سازگاری قدیمی؛ برای بسته‌های فعلی استفاده نمی‌شود.
  final int? dailyCap;

  /// تعداد کل اعتبار بسته؛ تمام بسته‌ها بدون انقضا هستند.
  final int? periodCap;

  final bool isGold;
  final bool isPopular;
  final bool isBestValue;
  final List<String> benefits;


  factory ShopPackage.fromJson(Map<String, dynamic> json) {
    final creditsRaw = json['credits'];
    final daysRaw = json['days'];
    final priceRaw = json['price'];
    final compareRaw = json['compareAtPrice'] ?? json['originalPrice'];
    final badge = (json['badge'] ?? '').toString();
    final id = (json['id'] ?? '').toString();
    final title = (json['title'] ?? json['name'] ?? id).toString();
    final subtitle = (json['subtitle'] ?? '').toString();
    final dailyCapRaw = json['dailyCap'];
    final periodCapRaw = json['periodCap'];
    return ShopPackage(
      id: id,
      title: title,
      subtitle: subtitle,
      priceToman: priceRaw is num ? priceRaw.round() : int.tryParse(priceRaw?.toString() ?? '') ?? 0,
      compareAtPriceToman: compareRaw is num ? compareRaw.round() : int.tryParse(compareRaw?.toString() ?? ''),
      credits: creditsRaw is num && creditsRaw > 0 ? creditsRaw.round() : null,
      days: daysRaw is num && daysRaw > 0 ? daysRaw.round() : null,
      dailyCap: dailyCapRaw is num && dailyCapRaw > 0 ? dailyCapRaw.round() : null,
      periodCap: periodCapRaw is num && periodCapRaw > 0 ? periodCapRaw.round() : null,
      isGold: (json['goldenDays'] is num && (json['goldenDays'] as num) > 0) || id.startsWith('gold_'),
      isPopular: json['highlight'] == true || badge.contains('محبوب'),
      isBestValue: badge.contains('ارزش') || badge.contains('به‌صرفه'),
      benefits: <String>[
        if (creditsRaw is num && creditsRaw > 0) creditsRaw.round().toString() + ' بار عیب‌یابی هوشمند',
        if (daysRaw is num && daysRaw > 0) daysRaw.round().toString() + ' روز دسترسی',
        if (dailyCapRaw is num && dailyCapRaw > 0) 'سقف روزانه: ' + dailyCapRaw.round().toString() + ' عیب‌یابی',
        if (periodCapRaw is num && periodCapRaw > 0) 'سقف دوره: ' + periodCapRaw.round().toString() + ' عیب‌یابی',
        if (json['monthlyLimit'] is num && (json['monthlyLimit'] as num) > 0) 'سقف ماهانه: ' + (json['monthlyLimit'] as num).round().toString() + ' عیب‌یابی',
        if (subtitle.isNotEmpty) subtitle,
      ],
    );
  }

  const ShopPackage({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.priceToman,
    this.compareAtPriceToman,
    this.credits,
    this.days,
    this.dailyCap,
    this.periodCap,
    this.isGold = false,
    this.isPopular = false,
    this.isBestValue = false,
    this.benefits = const [],
  });

  int? get unitPrice {
    if (credits != null && credits! > 0) {
      return (priceToman / credits!).round();
    }
    if (days != null && days! > 0) {
      return (priceToman / days!).round();
    }
    return null;
  }

  /// هزینه تقریبی هر عیب‌یابی بر اساس اعتبار کل بسته.
  int? get bestCaseUnitPrice {
    if (periodCap == null || periodCap! <= 0) return null;
    return (priceToman / periodCap!).round();
  }
}

/// سه بسته ساده برای نسخه کافه‌بازار؛ شناسه‌ها با محصولات مصرف‌شدنی بازار هماهنگ‌اند.
const shopPackages = <ShopPackage>[
  ShopPackage(
    id: 'credit_10',
    title: 'برنزی',
    subtitle: '۱۰ اعتبار عیب‌یابی',
    priceToman: 49000,
    credits: 10,
    benefits: [
      '۱۰ عیب‌یابی موفق',
      'بدون تاریخ انقضا',
      'مناسب استفاده گهگاهی',
    ],
  ),
  ShopPackage(
    id: 'credit_35',
    title: 'نقره‌ای',
    subtitle: '۲۵ اعتبار عیب‌یابی',
    priceToman: 99000,
    credits: 25,
    isPopular: true,
    benefits: [
      '۲۵ عیب‌یابی موفق',
      'بدون تاریخ انقضا',
      'هزینه کمتر برای هر عیب‌یابی',
    ],
  ),
  ShopPackage(
    id: 'credit_90',
    title: 'طلایی',
    subtitle: '۶۰ اعتبار عیب‌یابی',
    priceToman: 199000,
    credits: 60,
    isGold: true,
    isBestValue: true,
    benefits: [
      '۶۰ عیب‌یابی موفق',
      'بدون تاریخ انقضا و محدودیت روزانه',
      'مناسب استفاده پرتکرار با تخفیف پلکانی',
    ],
  ),
];
