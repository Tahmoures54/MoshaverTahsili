# مهاجرت داده و سازگاری نسخه دوم

## ۱. وضعیت موجود
داده‌های workspace در کلیدهای مستقل SharedPreferences نگهداری و از طریق `SecureLocalCipher` رمز می‌شوند. `AndroidKeystoreCipher` envelope با پیشوند `enc:v2:` می‌پذیرد. در شروع، داده‌های قدیمی plaintext به شکل encrypt → decrypt verify → persist مهاجرت می‌شوند؛ در صورت خطا داده قبلی بازنویسی نمی‌شود. کیف پول ساختار version=3 دارد و `_decodeWallet` مهاجرت نسخه‌های قدیمی‌تر را انجام می‌دهد. قالب backup فعلی `WorkspaceBackup.format=1` است و کلیدهای workspace را می‌پذیرد؛ wallet و purchase tokens عمداً از backup خارج‌اند.

## ۲. اصل مهاجرت
هیچ فیلد یا کلید موجود را در یک نسخه ناگهانی rename/delete نکنید. هر تغییر با migration مستقل، idempotent و قابل بازیابی انجام شود. مهاجرت باید در صورت crash، کمبود فضا یا خرابی ciphertext داده اصلی را حفظ کند.

## ۳. نسخه‌بندی
- `workspaceSchemaVersion` جدید به‌صورت metadata مستقل و پس از موفقیت تمام migrationها نوشته شود.
- نسخه wallet فعلی ۳ است؛ migration مالی فقط در ماژول wallet و با تست token idempotency.
- backup format فعلی ۱ است؛ نسخه ۲ باید decoder نسخه ۱ را حفظ کند و metadata جدید را اختیاری بخواند.
- نسخه الگوریتم SM-2 جدا از schema داده باشد؛ `schedulerVersion` روی کارت‌های جدید اختیاری.
- content pack version مستقل از نسخه اپ و schema محلی باشد.

## ۴. الگوی migration امن
1. بررسی فضای ذخیره‌سازی و نسخه فعلی.
2. خواندن و decrypt داده فعلی؛ هیچ write در این مرحله.
3. decode و validate با سقف حجم/تعداد/فیلد.
4. تبدیل در حافظه به ساختار جدید.
5. serialize و encrypt در کلید staging مانند `edu.profile.v2.staging`.
6. decrypt و validate staging.
7. نوشتن مقدار نهایی با کنترل موفقیت.
8. ثبت migration marker و سپس پاک‌سازی staging در اجرای بعدی.
اگر هر مرحله شکست خورد، staging حذف شود و کلید اصلی/نسخه اصلی دست‌نخورده بماند. migration هرگز wallet را از backup یا فایل وارد نکند.

## ۵. مهاجرت‌های پیشنهادی
| از | به | عملیات | خطر |
|---|---|---|---|
| profile legacy | profile schema v2 | افزودن فیلدهای optional و origin metadata | مقدار ناشناخته grade/field |
| tasks legacy | task v2 | افزودن goalId/chunkable بدون تغییر id/done/dueDate | تاریخ نامعتبر |
| cards legacy | scheduler v2 | نگهداری ease/interval/reps/lapses؛ افزودن schedulerVersion | تغییر ناخواسته موعد مرور |
| exams/deadlines | normalized records | افزودن source/scale/timezone اختیاری | نمره نامعتبر |
| backup format 1 | format 2 | decoder هر دو؛ wallet همچنان ممنوع | فایل ناقص/بزرگ |
| wallet v3 | فقط در صورت نیاز نسخه بعدی | حفظ balance/tokens/transactions/request idempotency | شارژ تکراری/از دست رفتن اعتبار |

## ۶. بازگشت و بازیابی
SharedPreferences تراکنش چندکلیدی ندارد؛ بنابراین rollback واقعی با rename اتمیک فرض نشود. برای migration چندکلیدی:
- backup رمز‌شده داخلی کوتاه‌عمر از همان کلیدهای درگیر؛
- staging per-key؛
- migration marker با مرحله؛
- اجرای مجدد idempotent؛
- اگر restore خودکار نامطمئن است، برنامه read-only شود و پیام واضح بدهد؛ هرگز داده را با default خالی جایگزین نکند.
قبل از release، restore از backup دستی و مهاجرت از fixture واقعی نسخه منتشرشده آزمون شود.

## ۷. سازگاری backup
- decoder نسخه ۱ باید دائماً تا پایان چرخه پشتیبانی نسخه‌های قدیمی باقی بماند.
- import ابتدا validate کامل، سپس preview تعداد رکوردها و تأیید کاربر.
- import نباید wallet، token خرید، secret یا consent والد را بازنویسی کند.
- ادغام یا جایگزینی داده باید صریح و قابل فهم باشد؛ پیش‌فرض replace خاموش.
- داده‌های واردشده untrusted هستند؛ طول، تعداد، URL و ساختار validate شوند.
- پس از import، داده‌ها با cipher دستگاه جاری encrypt شوند.

## ۸. تست‌های migration
- fixtures واقعی anonymized از نسخه جاری و legacy.
- crash در هر نقطه migration.
- ciphertext خراب یا کلید Keystore مفقود.
- فضای ناکافی/نوشتن ناموفق.
- اجرای مجدد migration.
- حفظ task/card/exam/profile ids و مقادیر.
- حفظ balance، tokenهای خرید و تراکنش‌ها بدون شارژ دوباره.
- backup v1 import به v2 و round-trip.
- اطمینان از عدم export/import wallet.
- rollback به حالت read-only بدون overwrite.
