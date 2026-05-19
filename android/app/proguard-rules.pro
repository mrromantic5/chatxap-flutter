# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.**

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Flutter InAppWebView
-keep class com.pichillilorenzo.flutter_inappwebview.** { *; }
-dontwarn com.pichillilorenzo.flutter_inappwebview.**

# Flutter Local Notifications
-keep class com.dexterous.** { *; }
-dontwarn com.dexterous.**

# AndroidX
-keep class androidx.** { *; }
-dontwarn androidx.**

# Kotlin
-keep class kotlin.** { *; }
-dontwarn kotlin.**

# Keep notification action receivers
-keep class * extends android.content.BroadcastReceiver { *; }
-keep class * extends android.app.Service { *; }

# url_launcher
-keep class io.flutter.plugins.urllauncher.** { *; }

# Connectivity
-keep class dev.fluttercommunity.plus.connectivity.** { *; }

# General
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
