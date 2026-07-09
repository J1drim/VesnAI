# R8/ProGuard keep rules for VesnAI.
#
# The Glance widget (androidx.glance:glance-appwidget) transitively pulls in
# WorkManager, which auto-initializes at startup via AndroidX App Startup and
# builds a Room database by reflection. R8 full mode (AGP 9) cannot see those
# reflective lookups, so without these rules it strips/renames the generated
# Room implementation and the app crashes on launch:
#   Failed to create an instance of androidx.work.impl.WorkDatabase

# --- AndroidX App Startup (InitializationProvider) ---
-keep class androidx.startup.** { *; }
-keep class * implements androidx.startup.Initializer { *; }

# --- WorkManager ---
-keep class androidx.work.** { *; }
-dontwarn androidx.work.**

# --- Room: keep databases and their generated *_Impl classes ---
-keep class androidx.room.** { *; }
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class **_Impl { <init>(...); }
-keepclassmembers class * extends androidx.room.RoomDatabase {
    <init>();
}
-dontwarn androidx.room.**

# --- Jetpack Glance widget ---
-keep class androidx.glance.** { *; }
-dontwarn androidx.glance.**
-keep class ai.vesnai.vesnai_app.widget.** { *; }

# Flutter deferred components (optional Play Core; not bundled in our APK)
-dontwarn com.google.android.play.core.**

# --- mobile_scanner / ML Kit barcode (R8 strips these in release) ---
# The plugin ships consumer rules with `com.google.mlkit.*` (single segment) which
# is too narrow; use recursive keeps so release APKs can open the camera.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }
-keep class com.google.android.libraries.barhopper.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode_bundled.** { *; }
-keep class com.google.photos.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**

# CameraX (mobile_scanner preview pipeline)
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**

# mobile_scanner plugin + method channel
-keep class dev.steenbakker.mobile_scanner.** { *; }

# Flutter plugins (method channels / Pigeon; needed on recent Flutter in release)
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }
