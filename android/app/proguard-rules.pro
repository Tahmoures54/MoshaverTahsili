# ═══════════════════════════════════════════════════════════
#  proguard-rules.pro – مشاور هوشمند تحصیلی (سیمرغ)
#  فعال‌شده با: minifyEnabled true, shrinkResources true
#  مسیر جایگزینی: android/app/proguard-rules.pro
# ═══════════════════════════════════════════════════════════

# ─────────────────────────────────────────────
#  0. Attributes و Stack Trace
# ─────────────────────────────────────────────
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-keepattributes SourceFile, LineNumberTable
-keepattributes RuntimeVisibleAnnotations
-keepattributes RuntimeInvisibleAnnotations
-keepattributes RuntimeVisibleParameterAnnotations
-keepattributes RuntimeInvisibleParameterAnnotations
-keepattributes AnnotationDefault

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
-keep class io.flutter.FlutterInjector { *; }
-keep class io.flutter.embedding.engine.loader.** { *; }
-dontwarn io.flutter.embedding.**

# ─────────────────────────────────────────────
#  2. Play Core (deferred components استفاده نمی‌شود)
# ─────────────────────────────────────────────
# Flutter references Play Core only for optional deferred-component delivery.
# This application does not ship deferred components, so do not package Play Core.
-dontwarn com.google.android.play.core.**

# ─────────────────────────────────────────────
#  3. Kotlin & Coroutines
# ─────────────────────────────────────────────
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }
-keep class kotlin.reflect.jvm.internal.** { *; }
-keepclassmembers class kotlin.Metadata { *; }
-dontwarn kotlin.**
-dontwarn kotlin.reflect.jvm.internal.**
-dontwarn kotlinx.coroutines.**

# ─────────────────────────────────────────────
#  4. Bazaar / CafeBazaar IAP
# ─────────────────────────────────────────────
-keep class com.android.vending.billing.** { *; }
-keep class ir.cafebazaar.pardakht.** { *; }
-keep interface com.android.vending.billing.IInAppBillingService { *; }
-keep class com.farsitel.bazaar.** { *; }
-dontwarn ir.cafebazaar.**

# ─────────────────────────────────────────────
#  5. JSON / Serialization (AI API responses)
# ─────────────────────────────────────────────
-keep class org.json.** { *; }
-dontwarn org.json.**

# Gson / Moshi (اگر از پلاگین‌های serialization استفاده می‌کنید)
-keep class com.google.gson.** { *; }
-keep class com.squareup.moshi.** { *; }
-keepnames @com.squareup.moshi.JsonClass class *
-keepclassmembers class * {
    @com.squareup.moshi.Json <methods>;
}

# ─────────────────────────────────────────────
#  6. AndroidX & Material
# ─────────────────────────────────────────────
-keep class androidx.** { *; }
-keep class androidx.lifecycle.** { *; }
-keep class androidx.core.** { *; }
-keep class androidx.security.** { *; }
-keep class androidx.window.** { *; }
-dontwarn androidx.**

# ─────────────────────────────────────────────
#  7. OkHttp / Networking
# ─────────────────────────────────────────────
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
-keepnames class okhttp3.internal.publicsuffix.PublicSuffixDatabase
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }

# TLS (مهم برای ارتباط با DeepSeek API)
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**

# ─────────────────────────────────────────────
#  8. Project-specific (سیمرغ)
# ─────────────────────────────────────────────
# MainActivity و method channel handlers
-keep class ir.moshaver.tahsili.** { *; }
-keep class ir.moshaver.tahsili.MainActivity { *; }
-keepclassmembers class ir.moshaver.tahsili.** { *; }

# ─────────────────────────────────────────────
#  9. Android Keystore (رمزنگاری محلی AES-GCM)
# ─────────────────────────────────────────────
-keep class java.security.** { *; }
-keep class javax.crypto.** { *; }
-keep class android.security.** { *; }
-keep class android.security.keystore.** { *; }
-keep class java.security.spec.** { *; }
-keep class javax.crypto.spec.** { *; }

# ─────────────────────────────────────────────
#  10. حذف لاگ در release (امنیت)
# ─────────────────────────────────────────────
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
    public static *** w(...);
    public static *** e(...);
    public static *** wtf(...);
}

# ─────────────────────────────────────────────
#  11. Optimization
# ─────────────────────────────────────────────
-allowaccessmodification
-repackageclasses
-mergeinterfaceaggressively

# ─────────────────────────────────────────────
#  12. عمومی
# ─────────────────────────────────────────────
-dontwarn sun.misc.**
-dontwarn java.lang.invoke.**
-dontwarn org.codehaus.mojo.animal_sniffer.**
-dontnote **
