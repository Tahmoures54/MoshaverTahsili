# Flutter embedding and plugin entry points.
-keep class io.flutter.** { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}

# This app does not use Play Store deferred components. Flutter keeps optional
# references in its embedding; suppress only those unused optional classes.
-dontwarn com.google.android.play.core.**

# Preserve runtime annotations and generic signatures.
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes EnclosingMethod
-keepattributes InnerClasses
