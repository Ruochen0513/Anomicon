# Anomicon Android Flutter

Flutter rewrite workspace for the Android target of the HarmonyOS-first Anomicon app.

## Current Scope

- Flutter app root lives in this `android/` directory.
- The generated Android platform shell lives under `android/android/`.
- Package/application ID is `com.suixin.anomicon`.
- The UI layer is being rebuilt to match the provided HarmonyOS showcase style: black canvas, deep gray cards, blue emphasis, large Chinese headings, and a translucent rounded bottom bar.

## Build

Prerequisites:

- Flutter 3.47 or compatible stable SDK
- JDK 17
- Android SDK with a recent platform installed

Commands:

```bash
cd android
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
```

The debug APK is produced at:

```text
android/build/app/outputs/flutter-apk/app-debug.apk
```
