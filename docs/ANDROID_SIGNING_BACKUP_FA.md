# پشتیبان امن کلید امضای اندروید

> این راهنما برای پشتیبان‌گیری از **کلید امضای فعلی** است. هرگز برای پشتیبان‌گیری کلید تازه تولید نکنید.

## ۱. آماده‌سازی

در GitHub به مسیر زیر بروید:

`Settings → Secrets and variables → Actions → New repository secret`

یک Secret با نام `SIGNING_BACKUP_PASSPHRASE` بسازید. مقدار آن باید دست‌کم ۲۴ نویسه تصادفی و قوی باشد. آن را در password manager یا محل امن آفلاین نگه دارید؛ این عبارت در مخزن یا گزارش‌های Actions نمایش داده نمی‌شود.

وجود این چهار Secret نیز ضروری است:

- `RELEASE_KEYSTORE_BASE64`
- `RELEASE_KEYSTORE_PASSWORD`
- `RELEASE_KEY_ALIAS`
- `RELEASE_KEY_PASSWORD`

## ۲. اجرای پشتیبان‌گیری

1. از زبانه Actions گردش‌کار **Export encrypted Android signing backup** را باز کنید.
2. شاخه `main` را انتخاب کنید.
3. در ورودی تأیید دقیقاً `BACKUP_EXISTING_KEY` را وارد و اجرا کنید.
4. پس از موفقیت، Artifact با نامی شبیه `android-signing-backup-...` را دانلود کنید.
5. فایل رمزگذاری‌شده را در دست‌کم دو محل آفلاین امن نگه دارید.

Artifact فقط هفت روز در GitHub باقی می‌ماند؛ آن را همان روز دانلود کنید. هیچ فایل JKS یا گذرواژه‌ای به‌صورت آشکار در Artifact قرار نمی‌گیرد.

## ۳. بازیابی در Windows

OpenSSL همراه Git for Windows معمولاً در این مسیر است:

`C:\Program Files\Git\usr\bin\openssl.exe`

در PowerShell، در پوشه فایل دانلودشده:

```powershell
$openssl = "C:\Program Files\Git\usr\bin\openssl.exe"
$pass = Read-Host "Backup passphrase" -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass)
try {
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
    $plain | & $openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -pass stdin -in .\android-signing-backup.tar.gz.enc -out .\android-signing-backup.tar.gz
    if ($LASTEXITCODE -ne 0) { throw "Decryption failed" }
}
finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    $plain = $null
}
tar -xzf .\android-signing-backup.tar.gz
```

فایل‌های استخراج‌شده شامل `upload-keystore.jks` و سه فایل متنی حاوی alias و گذرواژه‌ها هستند. این فایل‌ها را محرمانه نگه دارید.

## ۴. نکات حیاتی

- کلید امضا را دوباره تولید نکنید؛ تغییر کلید می‌تواند انتشار به‌روزرسانی برای نصب‌های قبلی را مختل کند.
- گذرواژه پشتیبان را جدا از Artifact نگه دارید.
- Artifact هفت‌روزه جایگزین پشتیبان آفلاین دائمی نیست.
- اگر از `GH_SECRETS_BOOTSTRAP_TOKEN` برای تولید کلید استفاده کرده‌اید، حذف Secret آن، خود Personal Access Token را باطل نمی‌کند؛ آن PAT را جداگانه از GitHub Settings → Developer settings → Personal access tokens لغو کنید.
- کلید عمومی RSA بازار از پنل توسعه‌دهندگان بازار دریافت می‌شود و با کلید امضای APK یکی نیست.
