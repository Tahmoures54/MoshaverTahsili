# 🎓 مشاور هوشمند تحصیلی

> همراه هوشمند دانش‌آموزان ایرانی در مسیر یادگیری، برنامه‌ریزی و انتخاب آگاهانه مسیر تحصیلی.

[![Flutter](https://img.shields.io/badge/Flutter-3.24.5-blue?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.5-blue?logo=dart)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android%20API%2024+-brightgreen)](https://developer.android.com)
[![CI](https://github.com/YOUR_USER/YOUR_REPO/actions/workflows/flutter.yml/badge.svg)](https://github.com/YOUR_USER/YOUR_REPO/actions)

---

## 📑 فهرست مطالب

- [امکانات](#-امکانات)
- [تصاویر برنامه](#-تصاویر-برنامه)
- [نصب و راه‌اندازی سریع](#-نصب-و-راه‌اندازی-سریع)
- [پیکربندی هوش مصنوعی](#-پیکربندی-هوش-مصنوعی)
- [خرید اعتبار از کافه‌بازار](#-خرید-اعتبار-از-کافه‌بازار)
- [ساختار پروژه](#-ساختار-پروژه)
- [معماری](#-معماری)
- [حریم خصوصی و امنیت](#-حریم-خصوصی-و-امنیت)
- [ساخت و امضای Android](#-ساخت-و-امضای-android)
- [کنترل کیفیت](#-کنترل-کیفیت)
- [محدودیت‌های نسخه پایه](#-محدودیت‌های-نسخه-پایه)
- [مشارکت](#-مشارکت)
- [مجوز](#-مجوز)

---

## ✨ امکانات

### 📋 مدیریت تحصیلی
- **پروفایل تحصیلی** قابل ویرایش؛ بدون ثبت‌نام اجباری یا دریافت شماره تلفن
- **برنامه‌ریز مطالعه** با گزارش هفت روز اخیر
- **ثبت نمره** و مشاهده میانگین عملکرد
- **فلش‌کارت** با مرور فاصله‌دار ساده

### 🤖 هوش مصنوعی
- **گفت‌وگوی فارسی** با مشاور هوش مصنوعی (OpenAI-compatible)
- **راهنمای انتخاب رشته** با تحلیل هوشمند
- **۲ درخواست موفق رایگان** و سپس اعتبار مصرفی
- خطاهای درخواست هزینه‌ای ندارند؛ اعتبار فقط پس از پاسخ موفق کسر می‌شود

### 💳 پرداخت و اعتبار
- **خرید بسته اعتبار** از کافه‌بازار (پرداخت درون‌برنامه‌ای)
- **کیف اعتبار محلی** روی گوشی
- **توکن یکتای خرید** در حافظه محلی؛ یک خرید دوبار شارژ نمی‌شود

### 📚 منابع آموزشی
- **راهنمای روش مطالعه**، تمرکز و آمادگی امتحان
- **نکات تکنیک پومودورو**، تکرار فاصله‌دار، هدف‌گذاری و خواب

### 💾 داده‌ها
- **ذخیره کامل روی دستگاه** (SharedPreferences)
- **امکان حذف داده‌ها** از داخل برنامه
- بدون نیاز به بک‌اند اختصاصی برای برنامه‌ریزی، نمرات و فلش‌کارت‌ها

---

## 📸 تصاویر برنامه

> ⚠️ تصاویر به‌زودی اضافه می‌شوند.

| خانه | برنامه‌ریز | مشاور AI |
|:---:|:---:|:---:|
| ![خانه](docs/screenshots/home.png) | ![برنامه](docs/screenshots/planner.png) | ![مشاور](docs/screenshots/advisor.png) |

---

## 🚀 نصب و راه‌اندازی سریع

### پیش‌نیازها
- [Flutter](https://flutter.dev/docs/get-started/install) ≥ 3.24.0
- [Dart](https://dart.dev/get-dart) ≥ 3.5.0
- Android SDK با API 24+
- JDK 17

### مراحل اجرا

```bash
# ۱) کلون مخزن
git clone https://github.com/YOUR_USER/YOUR_REPO.git
cd YOUR_REPO

# ۲) نصب وابستگی‌ها
flutter pub get

# ۳) اجرای محلی (بدون AI — امکانات محلی فعال)
flutter run

# ۴) اجرای محلی با هوش مصنوعی
flutter run --dart-define=AI_API_KEY=YOUR_KEY
جدول متغیرهای محیطی
متغیر	الزامی	پیش‌فرض	توضیح
AI_API_KEY	⚠️ برای AI	—	کلید API سرویس هوش مصنوعی
AI_API_ENDPOINT	خیر	https://api.avalai.ir/v1/chat/completions	آدرس سازگار با OpenAI Chat Completions
AI_MODEL	خیر	deepseek-chat	نام مدل
BAZAAR_RSA_PUBLIC_KEY	⚠️ برای IAP	—	کلید عمومی RSA پرداخت بازار
💡 اگر AI_API_KEY تنظیم نشود، امکانات محلی (برنامه‌ریز، آزمون، فلش‌کارت) فعال می‌مانند و صفحه مشاور پیام مناسب نشان می‌دهد.

🤖 پیکربندی هوش مصنوعی
نمونه ساخت کامل
Bash

flutter build apk --release \
  --dart-define=AI_API_KEY=YOUR_KEY \
  --dart-define=AI_API_ENDPOINT=https://api.avalai.ir/v1/chat/completions \
  --dart-define=AI_MODEL=deepseek-chat \
  --dart-define=BAZAAR_RSA_PUBLIC_KEY=YOUR_RSA_KEY
⚠️ هشدار امنیتی
هر کلیدی که داخل APK قرار بگیرد قابل استخراج است.

GitHub Actions Secrets مانع ثبت کلید در سورس عمومی می‌شود، اما کلید را داخل APK محرمانه نمی‌کند. برای انتشار عمومی، کلید محدودشده با سقف مصرف یا واسط امن سمت سرور راهکار مطمئن‌تری است.

💳 خرید اعتبار از کافه‌بازار
تنظیمات پنل توسعه‌دهندگان بازار
برای بسته ir.moshaver.tahsili سه محصول مصرف‌شدنی ایجاد کنید:

شناسه محصول	اعتبار	توضیح
credit_10	۱۰	بسته پایه
credit_35	۲۵	بسته پرفروش
credit_90	۶۰	بسته ویژه
قیمت هر بسته در پنل بازار تعیین می‌شود و داخل برنامه ثابت نشده است. شناسه‌ها باید دقیقاً با پنل بازار یکسان باشند.

تنظیم Secret در GitHub
Repository Secret	مقدار
BAZAAR_RSA_PUBLIC_KEY	کلید عمومی RSA از پنل بازار
GitHub Actions این مقدار را هنگام ساخت با --dart-define به برنامه تزریق می‌کند.

⚠️ محدودیت معماری بدون سرور
کیف اعتبار و دفتر توکن خرید فقط روی همان گوشی نگهداری می‌شوند. در نتیجه:

انتقال اعتبار بین گوشی‌ها ممکن نیست
بازیابی قطعی بعد از حذف برنامه تضمین نمی‌شود
جلوگیری سروری از دستکاری موجودی وجود ندارد
حذف فضای کاری دانش‌آموز، اعتبار خریداری‌شده و سابقه توکن را پاک نمی‌کند
این ریسک با معماری انتخاب‌شده پذیرفته شده است.

📁 ساختار پروژه
text

moshaver_tahsili/
├── lib/
│   ├── main.dart                        # نقطه ورود + Provider سراسری
│   ├── education_app.dart               # ویجت اصلی + ۵ تب + صفحات جانبی
│   └── education/
│       ├── education_store.dart         # مدیریت State (ChangeNotifier)
│       ├── ai_advisor_service.dart      # ارتباط با API هوش مصنوعی
│       ├── bazaar_billing_service.dart  # پرداخت درون‌برنامه‌ای بازار
│       └── credit_shop_page.dart        # صفحه خرید اعتبار
├── android/
│   ├── app/
│   │   ├── src/main/
│   │   │   ├── AndroidManifest.xml
│   │   │   ├── kotlin/.../MainActivity.kt
│   │   │   └── res/
│   │   │       ├── drawable/            # آیکون‌ها و اسپلش
│   │   │       ├── values/              # strings, colors
│   │   │       └── xml/                 # data_extraction_rules
│   │   ├── build.gradle
│   │   └── proguard-rules.pro
│   ├── build.gradle                     # ریشه
│   ├── settings.gradle
│   ├── gradle.properties
│   └── gradle/wrapper/
│       └── gradle-wrapper.properties
├── .github/workflows/
│   └── flutter.yml                      # CI/CD
├── analysis_options.yaml
├── pubspec.yaml
└── README.md
🏗️ معماری
لایه	فناوری	توضیح
فرانت‌اند	Flutter 3.24 / Dart 3.5	تک‌کدبیس Android
مدیریت State	Provider + ChangeNotifier	EducationStore سراسری
ذخیره‌سازی	SharedPreferences	داده‌های سبک محلی
شبکه	package:http	ارتباط با API هوش مصنوعی
پرداخت	cafebazaar_billing	IAP کافه‌بازار
CI/CD	GitHub Actions	ساخت خودکار APK
شناسه	ir.moshaver.tahsili	Android package name
حداقل API	24 (Android 7.0)	ARM 32 + 64 بیتی
🔒 حریم خصوصی و امنیت
داده‌هایی که ارسال می‌شوند (فقط هنگام استفاده از AI)
✅ متن پرسش کاربر
✅ مقطع، رشته و هدف تحصیلی پروفایل
✅ حداکثر ۲۴ پیام اخیر گفتگو
داده‌هایی که ارسال نمی‌شوند
❌ نمرات
❌ برنامه مطالعه
❌ فلش‌کارت‌ها
❌ شماره تلفن یا ایمیل
ذخیره‌سازی محلی
برنامه‌ها، نمرات، فلش‌کارت‌ها، پروفایل و تاریخچه گفتگو روی دستگاه ذخیره می‌شوند
اطلاعات محلی در نسخه فعلی رمزنگاری اختصاصی ندارند
قفل صفحه و امنیت خود گوشی را فعال نگه دارید
در نسخه پایه، داده‌ها بین دستگاه‌ها همگام‌سازی نمی‌شوند
🔐 ساخت و امضای Android
امضای Debug (پیش‌فرض)
GitHub Actions در نبود keystore خصوصی، APK را با امضای debug می‌سازد. این فایل برای نصب و آزمون قابل استفاده است ولی برای انتشار در بازار مناسب نیست.

امضای Release (انتشار)
۱) تنظیم Repository Secrets
Secret	توضیح
RELEASE_KEYSTORE_BASE64	محتوای Base64 فایل keystore
RELEASE_KEYSTORE_PASSWORD	رمز keystore
RELEASE_KEY_ALIAS	نام alias (مثلاً upload)
RELEASE_KEY_PASSWORD	رمز کلید
۲) ساخت keystore (روی رایانه محلی)
PowerShell

# ساخت کلید
keytool -genkeypair -v -keystore upload-keystore.jks `
  -storetype JKS -keyalg RSA -keysize 2048 `
  -validity 10000 -alias upload

# تبدیل به Base64 (برای Secret)
[Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks"))
۳) انتشار
نسخه را در pubspec.yaml افزایش دهید (مثلاً 1.0.2+3)
Tag بسازید: git tag v1.0.2 && git push origin v1.0.2
GitHub Actions APK امضاشده را در GitHub Release منتشر می‌کند
⚠️ Push عادی به main همچنان APK آزمایشی می‌سازد.

🚨 از فایل keystore و رمزها نسخه پشتیبان امن نگه دارید. از دست رفتن کلید انتشار می‌تواند به‌روزرسانی نسخه منتشرشده را مختل کند. کلید را در مخزن commit نکنید.

✅ کنترل کیفیت
Bash

flutter pub get
flutter analyze
flutter test
flutter build apk --release
⚠️ محدودیت‌های نسخه پایه
محدودیت	وضعیت
یادآوری اعلان‌محور (Notification)	🔜 برنامه‌ریزی‌شده
همگام‌سازی ابری	🔜 برنامه‌ریزی‌شده
تحلیل انتخاب رشته	⚠️ راهنمای اولیه؛ جایگزین مشاور مدرسه نیست
دقت پاسخ‌های AI	⚠️ ممکن است اشتباه باشند؛ با منابع رسمی بررسی کنید
رمزنگاری داده‌های محلی	🔜 برنامه‌ریزی‌شده
🤝 مشارکت
از مشارکت شما استقبال می‌شود! لطفاً:

مخزن را Fork کنید
شاخه جدید بسازید: git checkout -b feature/amazing-feature
تغییرات را Commit کنید: git commit -m 'feat: افزودن قابلیت جدید'
Push کنید: git push origin feature/amazing-feature
Pull Request باز کنید
قراردادهای کد
زبان کد و کامنت‌ها: فارسی
جهت اپ: RTL
فرمت‌بندی: dart format .
تحلیل: flutter analyze بدون خطا
📄 مجوز
این پروژه تحت مجوز MIT منتشر شده است.

text


---

### جدول خلاصه تغییرات

| تغییر | چرا | تأثیر |
|-------|-----|-------|
| Badge‌های Flutter/Dart/License/CI | اطلاعات سریع بصری | 🎨 حرفه‌ای‌تر |
| فهرست مطالب با لینک | ناوبری آسان در README طولانی | 📑 خوانایی |
| دسته‌بندی امکانات با emoji | گروه‌بندی منطقی | ✨ خوانایی |
| بخش «نصب و راه‌اندازی سریع» | راهنمای شروع برای توسعه‌دهنده جدید | 🚀 کاربردی |
| جدول متغیرهای محیطی | تجمیع ۴ متغیر پراکنده در یک جا | 📊 شفافیت |
| جدول محصولات بازار | خوانایی بهتر از لیست متنی | 💳 شفافیت |
| ساختار پوشه پروژه | راهنمای مشارکت‌کنندگان | 📁 ناوبری |
| جدول معماری | جداسازی از حریم خصوصی | 🏗️ شفافیت |
| بخش حریم خصوصی جدا | ✅/❌ بصری برای داده‌های ارسالی | 🔒 اعتماد کاربر |
| جدول محدودیت‌ها | وضعیت هر محدودیت مشخص | ⚠️ شفافیت |
| بخش مشارکت | استاندارد متن‌باز | 🤝 جامعه |
| محل تصاویر (placeholder) | آماده برای اسکرین‌شات | 📸 آینده‌نگری |
| `BAZAAR_RSA_PUBLIC_KEY` در نمونه build | سازگاری با بخش CI | 🔧 صحت |

---

> 📋 **جایگزینی:** کل کد بالا را در `README.md` (ریشه پروژه) کپی کنید. لینک‌های `YOUR_USER/YOUR_REPO` را با نام واقعی مخزن GitHub خود جایگزین کنید. ✅
