# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.**

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**

# Crashlytics
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception
-keep class com.google.firebase.crashlytics.** { *; }

# Flutter InAppWebView
-keep class com.pichillilorenzo.flutter_inappwebview.** { *; }
-dontwarn com.pichillilorenzo.flutter_inappwebview.**

# Flutter Local Notifications
-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**

# ── Biometric / Local Auth ────────────────────────────────────────────────────
# flutter local_auth plugin classes
-keep class io.flutter.plugins.localauth.** { *; }
-dontwarn io.flutter.plugins.localauth.**
# AndroidX BiometricPrompt (used internally by local_auth)
-keep class androidx.biometric.** { *; }
-dontwarn androidx.biometric.**

# ── Secure Storage ────────────────────────────────────────────────────────────
# flutter_secure_storage uses EncryptedSharedPreferences backed by Keystore.
# These rules prevent R8 from stripping the androidx.security classes it uses.
-keep class androidx.security.crypto.** { *; }
-dontwarn androidx.security.crypto.**
# The plugin itself
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn com.it_nomads.fluttersecurestorage.**

# ── Crypto (Dart package uses JVM MessageDigest via JNI — no extra rules) ────

# App Badger
-keep class fr.g123k.flutterapplicationbadger.** { *; }

# In App Update
-keep class com.google.android.play.core.** { *; }

# AndroidX
-keep class androidx.** { *; }
-dontwarn androidx.**

# Kotlin
-keep class kotlin.** { *; }
-dontwarn kotlin.**

# Keep receivers
-keep class * extends android.content.BroadcastReceiver { *; }
-keep class * extends android.app.Service { *; }

# General
-keepattributes *Annotation*
-renamesourcefileattribute SourceFile
