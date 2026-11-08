# ═══════════════════════════════════════════════════════════
#  proguard-rules.pro – مشاور هوشمند تحصیلی
#  فعال‌شده با: minifyEnabled true, shrinkResources true
# ═══════════════════════════════════════════════════════════

# ─────────────────────────────────────────────
#  1. Flutter Engine (حیاتی – بدون این کرش)
# ─────────────────────────────────────────────
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }

# ─────────────────────────────────────────────
#  2. Play Core (deferred components استفاده نمی‌شود)
# ─────────────────────────────────────────────
-dontwarn com.google.android.play.core.**

# ─────────────────────────────────────────────
#  3. Kotlin & Coroutines
# ─────────────────────────────────────────────
-keep class kotlin.Metadata { *; }
-keep class kotlin.reflect.jvm.internal.** { *; }
-dontwarn kotlin.reflect.jvm.internal.**
-dontwarn kotlinx.coroutines.**

# ─────────────────────────────────────────────
#  4. Bazaar / CafeBazaar IAP
# ─────────────────────────────────────────────
-keep class com.android.vending.billing.** { *; }
-keep class ir.cafebazaar.pardakht.** { *; }
-keep interface com.android.vending.billing.IInAppBillingService { *; }

# ─────────────────────────────────────────────
#  5. JSON / Serialization (AI API responses)
# ─────────────────────────────────────────────
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# ─────────────────────────────────────────────
#  6. AndroidX & Material
# ─────────────────────────────────────────────
-keep class androidx.lifecycle.** { *; }
-keep class androidx.core.** { *; }
-dontwarn androidx.**

# ─────────────────────────────────────────────
#  7. OkHttp / Networking (اگر پلاگین HTTP دارید)
# ─────────────────────────────────────────────
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
-keepnames class okhttp3.internal.publicsuffix.PublicSuffixDatabase

# ─────────────────────────────────────────────
#  8. عمومی
# ─────────────────────────────────────────────
-dontwarn sun.misc.**
-dontwarn java.lang.invoke.**
-dontwarn org.codehaus.mojo.animal_sniffer.**# Flutter references Play Core only for optional deferred-component delivery.
# This application does not ship deferred components, so do not package Play Core.
-dontwarn com.google.android.play.core.**
