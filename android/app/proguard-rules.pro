# R8 rules for the release build.
#
# Only rules that are actually needed are here. A blanket `-keep class **` would
# make the build "work" while defeating the point of shrinking, and would hide
# the next real problem behind 4 MB of retained classes.

# ---- ML Kit ----------------------------------------------------------------
#
# Both ML Kit surfaces resolve implementation classes through the Play Services
# component registry rather than direct references, so R8 sees them as
# unreachable and strips them. The failure is release-only and looks like a
# scanner that never starts or recognition that always fails — which is why it
# is invariably found the week of submission.
-keep class com.google.mlkit.** { *; }
-keep interface com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }

# The document scanner is an on-demand Play Services module. Its entry points
# are looked up by name when the module is delivered.
-keep class com.google.android.gms.vision.** { *; }
-keep class com.google.android.gms.common.** { *; }

# ML Kit ships optional integrations it does not require; R8 warns about the
# ones that are absent. They are genuinely absent, and that is fine.
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.internal.mlkit_**

# ---- Plugin entry points ---------------------------------------------------
#
# Flutter plugins are instantiated reflectively by GeneratedPluginRegistrant.
-keep class io.flutter.plugins.** { *; }
-keep class dev.fluttercommunity.plus.share.** { *; }
-keep class com.google_mlkit_document_scanner.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
-keep class com.google_mlkit_commons.** { *; }

# ---- Our own platform channel ----------------------------------------------
#
# MainActivity is named in the manifest, so R8 keeps the class — but the
# Play Services availability check inside it is reached only from Dart.
-keep class com.sidrahayat.docuai.MainActivity { *; }

# ---- Kotlin ----------------------------------------------------------------
-dontwarn kotlin.**
-keepattributes *Annotation*

# Line numbers in a crash trace are worth the handful of kilobytes; without
# them a stack trace from a release build names methods but not positions.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
