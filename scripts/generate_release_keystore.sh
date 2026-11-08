#!/usr/bin/env bash
# تولید یک‌باره کلید امضای انتشار Android
# خروجی را در گیت commit نکنید. فقط در GitHub Secrets و نسخه پشتیبان امن نگه دارید.
set -euo pipefail

OUT_DIR="${1:-secrets}"
mkdir -p "$OUT_DIR"

if compgen -G "$OUT_DIR/*.jks" > /dev/null; then
  echo "یک فایل کلید امضای انتشار از قبل در $OUT_DIR وجود دارد."
  echo "برای جلوگیری از از دست رفتن کلید قبلی، تولید مجدد انجام نشد."
  exit 1
fi

STORE_PASS="$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-28)"
KEY_ALIAS="upload"
KEYSTORE="$OUT_DIR/android-release-upload.jks"

keytool -genkeypair -v \
  -keystore "$KEYSTORE" \
  -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias "$KEY_ALIAS" \
  -storepass "$STORE_PASS" \
  -keypass "$STORE_PASS" \
  -dname "CN=Smart Mechanic, OU=Android, O=Smart Mec, L=Tehran, ST=Tehran, C=IR"

base64 -w0 "$KEYSTORE" > "$OUT_DIR/RELEASE_KEYSTORE.base64"

cat > "$OUT_DIR/github-secrets.txt" <<EOF
# این فایل را در گیت نگذارید.
# مقادیر را در GitHub → Settings → Secrets and variables → Actions ذخیره کنید.
# همین کلید را برای همه نسخه‌های به‌روزرسانی‌شونده نگه دارید.
# اگر این کلید گم شود، به‌روزرسانی اپ در فروشگاه‌ها ممکن نیست.

RELEASE_KEY_ALIAS=$KEY_ALIAS
RELEASE_KEYSTORE_PASSWORD=$STORE_PASS
RELEASE_KEY_PASSWORD=$STORE_PASS

# مقدار RELEASE_KEYSTORE_BASE64 را از فایل RELEASE_KEYSTORE.base64 کپی کنید.
EOF

keytool -list -v \
  -keystore "$KEYSTORE" \
  -storepass "$STORE_PASS" \
  -alias "$KEY_ALIAS" | tee "$OUT_DIR/certificate-info.txt" >/dev/null

echo "کلید انتشار ساخته شد:"
echo "  $KEYSTORE"
echo "  $OUT_DIR/github-secrets.txt"
echo "  $OUT_DIR/RELEASE_KEYSTORE.base64"
echo "این فایل‌ها را در جای امن نگه دارید و هرگز در مخزن عمومی commit نکنید."
