# Anomicon Android

Android migration workspace for the HarmonyOS-first Anomicon app.

## Current Scope

- Native Android app under `android/app` using Kotlin, Jetpack Compose, Material 3, and a standard Gradle wrapper.
- Four primary home tabs matching the HarmonyOS product shape: Explore, Catalog, Stories, and Terminal.
- SCP Chinese Wiki catalog, story, and explore pages load through OkHttp + Jsoup with local seed fallbacks.
- Article reading opens the normalized SCP Wiki page in an in-app WebView and records local reading history.
- Settings persist theme, haptics, immersive material preference, font size, and line height with SharedPreferences.
- 3D archive metadata is ported and bundled GLB files are exposed to Android through Gradle assets source sets.

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
- ArkGraphics3D rendering is not yet replaced with an Android renderer. The migration preserves manifest, attribution, delivery policy, and packaged GLB access so SceneView/Filament can be introduced as a follow-up.
