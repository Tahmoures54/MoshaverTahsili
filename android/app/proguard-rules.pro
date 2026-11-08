# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Google Maps / Play Services
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# flutter_sound / audio
-dontwarn com.dooboolab.**
-keep class com.dooboolab.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Gson / JSON if any
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# OkHttp / platform
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
