# Anomicon Android

Android migration workspace for the HarmonyOS-first Anomicon app.

## Current Scope

- Native Android app under `android/app` using Kotlin, Jetpack Compose, Material 3, and a standard Gradle wrapper.
- Four primary home tabs matching the HarmonyOS product shape: Explore, Catalog, Stories, and Terminal.
- SCP Chinese Wiki catalog, story, and explore pages load through OkHttp + Jsoup with local seed fallbacks.
- Article pages are parsed into native Compose blocks, with cached images, image preview, adjustable font size/line height, and restored scroll position.
- Favorites, reading history, active reading time, researched-content count, XP, level progress, and continue-reading entries persist locally.
- Settings persist theme, haptics, immersive material preference, font size, and line height with SharedPreferences; haptic feedback and system-bar behavior are mapped to Android APIs.
- 3D archive metadata is ported; bundled and on-demand GLB files render through SceneView/Filament with download progress, size/SHA-256 verification, atomic install, and deletion.

## Build

Prerequisites:

- JDK 17
- Android SDK platform 35
- Android SDK build-tools 35.0.0 or newer compatible build-tools

Commands:

```bash
cd android
ANDROID_HOME=/path/to/android-sdk JAVA_HOME=/path/to/jdk17 ./gradlew assembleDebug
ANDROID_HOME=/path/to/android-sdk JAVA_HOME=/path/to/jdk17 ./gradlew testDebugUnitTest
```

The debug APK is produced at:

```text
android/app/build/outputs/apk/debug/app-debug.apk
```

## Migration Notes

- The HarmonyOS source tree remains untouched; Android is currently an additive platform target.
- ArkUI/HDS navigation maps to Compose `Scaffold`, `TopAppBar`, `NavigationBar`, chips, and cards.
- ArkData RDB and Preferences are represented by Android local storage seams for now.
- ArkGraphics3D rendering is replaced by SceneView/Filament for Android.
- Android activity tracking uses bounded foreground read intervals derived from article visibility and scroll checkpoints; it is intentionally local and does not claim background reading time.
- Device or emulator visual validation was not available in this workspace; build and JVM tests are the available verification gates.
