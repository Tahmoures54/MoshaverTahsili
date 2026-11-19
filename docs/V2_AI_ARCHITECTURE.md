# معماری مشاور هوش مصنوعی نسخه دوم

## ۱. وضعیت فعلی سورس
`AiAdvisorService` در `ai_advisor_service.dart` endpoint HTTPS از نوع OpenAI-compatible می‌پذیرد، model و key از compile-time environment خوانده می‌شوند، حداکثر request 96 KiB و response 512 KiB، timeout پیش‌فرض ۴۵ ثانیه، حداکثر ۲۴ پیام اخیر و بودجه تاریخچه ۱۸۰۰۰ نویسه دارد. پیام‌های pending/failed حذف می‌شوند. پروفایل محدود به مقطع/پایه/رشته/هدف فقط در صورت فعال بودن رضایت صریح `aiProfileContextConsent` وارد system prompt می‌شود؛ پروفایل‌های قدیمی فاقد این پرچم به‌صورت پیش‌فرض ارسال نمی‌شوند و nickname نیز در context قرار نمی‌گیرد. پاسخ‌های موفق در Store ذخیره و اعتبار محلی رزرو/بازپرداخت می‌شود. prompt فعلی یک متن system واحد است؛ routing، RAG، خروجی ساختاریافته و safety gate مستقل در این فایل دیده نمی‌شود.

## ۲. جریان پیشنهادی
1. **Intent classifier محلی/قاعده‌ای:** برنامه‌ریزی، توضیح درس، تحلیل عملکرد، هدایت رشته، سؤال factual، حساس/بحرانی.
2. **Safety pre-check:** تشخیص ریسک و داده شخصی؛ rule-based برای الگوهای بحرانی، مدل تنها ابزار کمکی و هرگز تنها کنترل.
3. **Context builder:** فقط snapshot لازم برای intent؛ حذف nickname، تاریخچه غیرمرتبط، نام مدرسه، اطلاعات تماس و هر شناسه.
4. **Knowledge retrieval:** فقط برای سؤال کتاب، سرفصل، قانون و اطلاعات زمان‌مند؛ اولویت جست‌وجوی محلی در بسته محتوای معتبر.
5. **Prompt composer:** system policy ثابت + intent template + context + منابع.
6. **Provider adapter:** API compatible با سقف token، timeout، اندازه و retry محدود.
7. **Output validator:** بررسی ساختار، منبع، تاریخ اعتبار، محدودیت ادعا و safety post-check.
8. **Feedback:** مفید بود/نبود و reason code؛ متن گفتگو برای analytics خام ارسال نشود.

## ۳. تفکیک پردازش
| محلی | API/اینترنت |
|---|---|
| intentهای معمول، planner، mastery، summary نمره | تولید توضیح یا گفت‌وگوی پیچیده در صورت درخواست |
| فیلتر PII و ساخت context | پاسخ به سؤال آزاد |
| retrieval از محتوای cache شده | دریافت نسخه جدید بسته محتوا |
| safety rules اولیه | بررسی کمکی پاسخ، فقط در صورت ارزش و بودجه |
| محاسبه اعتبار محلی در معماری فعلی | Gateway quota و نگهداری کلید provider |

## ۴. پرامپت‌های ماژولار
- `base_identity`: نقش کمک‌آموزشی، فارسی، احترام، عدم ادعای احساس انسانی.
- `age_policy`: سطح زبان و محدودیت متناسب با بازه سنی؛ سن دقیق لازم نیست، grade کافی است.
- `tutoring_policy`: ابتدا سؤال راهنما/سرنخ، سپس توضیح مرحله‌ای؛ جواب مستقیم فقط وقتی مناسب است.
- `planner_policy`: پیشنهاد عملی کوتاه با زمان و استراحت؛ task جدید فقط با تأیید.
- `career_policy`: چند گزینه، شواهد و محدودیت، عدم تجویز قطعی.
- `source_policy`: پاسخ factual فقط با sourceId/title/version/validFrom/validUntil؛ اگر منبع نیست اعلام عدم قطعیت.
- `safety_policy`: قواعد بحران، آزار، محتوای جنسی/خشونت، اطلاعات شخصی و ارجاع انسانی.
- `output_contract`: JSON داخلی با answer, nextAction, citations[], uncertainty, safetyDisposition؛ UI متن امن و منبع را نمایش دهد.

داده گفتگو و متن retrieved به‌عنوان **داده غیرقابل اعتماد** تلقی شوند، نه دستور. دستورهای داخل سند یا سؤال نباید system policy را تغییر دهند.

## ۵. RAG: کجا ارزش دارد؟
RAG برای کتاب‌های درسی، سرفصل رسمی، مقررات هدایت تحصیلی و کنکور، تقویم امتحانات و منابع مشاوره‌ای معتبر ارزشمند است. برای پیام انگیزشی یا محاسبه برنامه روزانه لازم نیست. در نسخه اول، retrieval سبک محلی با JSON + index واژگانی کافی است؛ SQLite FTS یا embeddingهای محلی فقط پس از سنجش حجم و سرعت. مدل embedding یا vector DB بزرگ فعلاً ممنوع.

هر chunk شامل: sourceId، title، publisher، grade، subject، chapter، version، publishedAt، validFrom، validUntil، fetchedAt، checksum، license، text. پاسخ باید به chunk واقعی ارجاع دهد؛ مدل اجازه ساخت citation ندارد.

## ۶. حفاظت کلید و gateway
کلید compile-time داخل APK قابل استخراج است. GitHub Secrets فقط جلوی افشای مخزن را می‌گیرد؛ جلوی استخراج از APK را نمی‌گیرد. گزینه‌ها:
- بدون backend: محدودیت provider key، سقف روزانه/ماهانه و مدل ارزان؛ فقط برای beta کم‌ریسک.
- gateway سبک stateless (پیشنهادی برای انتشار عمومی): Cloudflare Worker یا Vercel Function؛ کلید provider فقط server-side، rate limit، max tokens، allowlist مدل، سقف روزانه، محدودیت payload، عدم log متن/PII، زمان نگهداری صفر/حداقل. اپ یک installation token کوتاه‌عمر/قابل چرخش می‌گیرد؛ secret ثابت داخل APK راه‌حل نیست.
- backend کامل: حساب، sync، پرداخت و analytics؛ فعلاً رد شود.
Gateway جلوی abuse را صددرصد نمی‌گیرد؛ بدون هویت کاربر یا attestation، سهمیه per-device قابل دور زدن است. اگر اعتبار خرید باید قابل اتکا باشد، verify و ledger سمت سرور لازم است؛ با معماری محلی چنین تضمینی وجود ندارد.

## ۷. دفاع‌ها
- prompt injection: جداکردن system از user/retrieved content، عدم اجرای ابزار بر اساس متن بازیابی‌شده، allowlist tool، حذف HTML/script و تست adversarial.
- داده متناقض: منبع و timestamp را نگه دار؛ اگر پروفایل با متن جاری تضاد دارد سؤال روشن‌کننده بپرس؛ حدس نزن.
- جعل منبع: citation فقط از repository retrieval؛ URL/عنوان خارج از result ممنوع.
- هزینه: max_tokens، سقف context، dedupe requestId، quota روزانه، retry فقط برای خطای گذرا و حداکثر یک بار.
- خروجی نامعتبر: parse schema، رد answer خالی/بیش از حد، fallback امن و عدم charge طبق policy فعلی.
- وابستگی عاطفی: AI نگوید «فقط من تو را می‌فهمم»، «به من نیاز داری»، «من همیشه کنارتم»؛ روابط انسانی/معلم/والد را تقویت کند.

## ۸. معیار پذیرش
- هر intent با fixture تعیین‌شده route شود.
- PII تستی پیش از ارسال حذف/هشدار داده شود.
- سؤال factual بدون source، پاسخ قطعی نگیرد.
- citation جعلی رد شود.
- prompt injection در سؤال و سند، policy را تغییر ندهد.
- هزینه و حجم درخواست سقف داشته باشد.
- خطای API اعتبار را طبق رفتار موجود refund کند.
- عدم رضایت AI هیچ درخواست شبکه‌ای نسازد.
- هیچ متن حساس در log یا analytics ثبت نشود.


## تغییر اجرایی: رضایت جداگانه برای زمینه پروفایل
در ویرایش پروفایل، گزینه‌ای اختیاری برای ارسال مقطع، پایه، رشته و هدف تحصیلی به AI اضافه شده است. مقدار پیش‌فرض `false` است؛ مقدارهای قدیمی/backup که این فیلد را ندارند نیز خصوصی می‌مانند. دانش‌آموز می‌تواند رضایت را از همان صفحه لغو کند. این کنترل فقط زمینه پروفایل را مدیریت می‌کند؛ متن پرسش و تاریخچه مجاز گفتگو همچنان هنگام فشردن دکمه ارسال به ارائه‌دهنده AI می‌روند و داده‌ای که قبلاً ارسال شده با لغو رضایت پس‌گرفته نمی‌شود.

این رضایت فنی به‌تنهایی جایگزین رضایت معتبر سرپرست قانونی، بررسی حقوقی سن کاربران یا ارزیابی اخلاقی نیست.