# Oina Games for Android

Kotlin + Jetpack Compose port of the iOS app.

- Open this folder in Android Studio, or run `./gradlew :app:assembleDebug`.
- Localization is shared with iOS: run `python3 android/tools/convert_strings.py` after editing the
  `*.lproj/Localizable.strings` files to refresh `app/src/main/assets/l10n/*.json`.
- Add a game: a case in `core/Games.kt`, an engine + composable in `games/`, and a line in `games/GameHost.kt`.

Ported so far: 2048, Snake, Minesweeper, Quick Math, Simon, Lights Out.

## Game coverage

All iOS games are ported: 52 visible games plus the hidden ones (Togyzkumalak, Altybakan, Kokpar, Baige, Asyk, Crossword), which are listed in `GameId.hidden` in `core/Games.kt`. Remove an id from that set to show it.

Not ported yet: Firebase analytics, tutorials, confetti, bundled sound assets (tones only), saved/resumed rounds.

## Release build for Google Play

1. Create an upload key once (keep the file and passwords safe, never commit them):
   `keytool -genkeypair -v -keystore ~/oina-upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000`
2. Create `android/keystore.properties`:
   ```
   storeFile=/Users/you/oina-upload.jks
   storePassword=...
   keyAlias=upload
   keyPassword=...
   ```
3. Raise `versionCode` in `app/build.gradle.kts` for every upload.
4. `./gradlew :app:bundleRelease` produces `app/build/outputs/bundle/release/app-release.aab` (upload this to Play Console).
   `./gradlew :app:assembleRelease` produces a signed APK for sideloading.
