# Flutter / Plugins
-keep class io.flutter.** { *; }
-keep class io.flutter.plugin.** { *; }

# speech_to_text (com.csdcorp.speech_to_text)
-keep class com.csdcorp.speech_to_text.** { *; }
-keep class android.speech.** { *; }

# Firebase Auth + Google Sign-In Reflection
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# Crashlytics keeps line numbers
-keepattributes SourceFile,LineNumberTable
