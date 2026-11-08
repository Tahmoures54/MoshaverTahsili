import 'package:flutter_test/flutter_test.dart';

import 'package:smart_mechanic/models/shop_package.dart';

void main() {
  group('پلن‌های فروش — قیمت‌گذاری نسخه بازار', () {
    test('قیمت هر عیب‌یابی در هیچ بسته‌ای بیش از ۴٬۹۰۰ تومان نیست', () {
      const anchor = 4900;
      for (final pkg in shopPackages) {
        final unit = pkg.bestCaseUnitPrice ?? pkg.unitPrice;
        expect(
          unit,
          lessThanOrEqualTo(anchor),
          reason: 'واحد قیمت «${pkg.title}» از سقف ۴۹۰۰ تومان بیشتر است',
        );
      }
    });

    test('ارزان‌ترین بسته از ۴۹٬۰۰۰ تومان شروع می‌شود', () {
      final creditPacks = shopPackages.where((p) => !p.isGold).toList();
      expect(creditPacks.map((p) => p.priceToman).reduce((a, b) => a < b ? a : b), 49000);
    });

    test('تخفیف پلکانی: بستهٔ بزرگ‌تر هرگز گران‌ترِ واحد نیست', () {
      final creditPacks = shopPackages.where((p) => p.credits != null).toList()
        ..sort((a, b) => a.credits!.compareTo(b.credits!));

      for (var i = 1; i < creditPacks.length; i++) {
        final smaller = creditPacks[i - 1].unitPrice!;
        final larger = creditPacks[i].unitPrice!;
        expect(
          larger,
          lessThanOrEqualTo(smaller),
          reason:
              'واحد قیمت «${creditPacks[i].title}» نباید از بستهٔ کوچک‌تر بیشتر باشد',
        );
      }
    });

    test('فقط سه بسته برنزی، نقره‌ای و طلایی با اعتبار ثابت وجود دارد', () {
      expect(shopPackages, hasLength(3));
      expect(shopPackages.map((p) => p.title), ['برنزی', 'نقره‌ای', 'طلایی']);
      expect(shopPackages.map((p) => p.credits), [10, 25, 60]);
      expect(shopPackages.map((p) => p.priceToman), [49000, 99000, 199000]);
      expect(shopPackages.every((p) => p.days == null), isTrue);
      expect(shopPackages.every((p) => p.dailyCap == null), isTrue);
    });

    test('قیمت مقایسه‌ای (خط‌خورده) همیشه از قیمت واقعی بیشتر است', () {
      for (final pkg in shopPackages) {
        final compare = pkg.compareAtPriceToman;
        if (compare == null) continue;
        expect(compare, greaterThan(pkg.priceToman),
            reason: '«${pkg.title}»: قیمت مقایسه‌ای نامعتبر است');
      }
    });

    test('شناسه‌ها یکتا و هم‌تراز با PRICING.md هستند', () {
      final ids = shopPackages.map((p) => p.id).toSet();
      expect(ids.length, shopPackages.length);
      expect(
        ids,
        containsAll(<String>[
          'credit_10',
          'credit_35',
          'credit_90',
        ]),
      );
    });

    test('بج‌های محبوب/بیشترین‌صرفه هر کدام فقط به یک بسته داده شده', () {
      expect(
        shopPackages.where((p) => p.isPopular).length,
        1,
        reason: 'فقط یک بسته باید «محبوب» باشد',
      );
      expect(
        shopPackages.where((p) => p.isBestValue).length,
        1,
        reason: 'فقط یک بسته باید «بیشترین صرفه» باشد',
      );
    });

    test('همه بسته‌ها اعتبار مشخص و بدون انقضا دارند', () {
      for (final pkg in shopPackages) {
        expect(pkg.credits, greaterThan(0));
        expect(pkg.days, isNull);
      }
    });
  });
}
