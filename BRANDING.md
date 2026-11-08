# برندینگ — مکانیک هوشمند

## هویت

| مورد | مقدار |
|------|--------|
| نام فارسی | مکانیک هوشمند |
| نام انگلیسی | Smart Mechanic |
| کوتاه | Smart Mec |
| شعار | بزرگترین بانک اطلاعات فنی خودرویی کشور |
| پکیج | `ir.smartmec.app` |
| حس برند | کارگاهی · نارنجی ابزار · اعتماد |

منبع لوگو: نشان دایره‌ای — چرخ‌دنده برنزی، قفل و ابزار **نارنجی** روی زمینه گرم تیره.

کد: `lib/theme/brand.dart` و ویجت `lib/widgets/brand_logo.dart`.

## پالت رنگ

| نقش | رنگ | هگز |
|-----|------|-----|
| نارنجی اصلی | Orange | `#FF7A1A` |
| نارنجی روشن | Orange Light | `#FFCC80` |
| نارنجی عمیق | Orange Deep | `#E65100` |
| زنگ / لبه | Rust | `#BF360C` |
| چرخ‌دنده | Bronze gear | `#5A3A28` |
| پس‌زمینه لانچر | Dark warm | `#140C08` |
| دیسک داخلی | Disc | `#24140C` |

## آیکون لانچر (روی گوشی)

آیکون نصب از `assets/branding/app_icon.png` و لایه‌های Adaptive ساخته می‌شود:

| فایل | کاربرد |
|------|--------|
| `app_icon.png` | آیکون لانچر ۱۰۲۴×۱۰۲۴ |
| `app_icon_foreground.png` | لایه Adaptive |
| `splash_mark.png` | اسپلش |
| `play_store_icon.png` | فروشگاه |

### تولید مجدد (محلی)

```bash
pip3 install pillow
python3 tool/generate_branding.py
flutter pub get
dart run flutter_launcher_icons
# اختیاری:
dart run flutter_native_splash:create
```

در CI همین مراحل قبل از بیلد APK اجرا می‌شود تا آیکون نارنجی روی گوشی بیاید.

تنظیمات `pubspec.yaml` → `flutter_launcher_icons`:
- `image_path`: `assets/branding/app_icon.png`
- `adaptive_icon_background`: `#140C08`
- `adaptive_icon_foreground`: `assets/branding/app_icon_foreground.png`
