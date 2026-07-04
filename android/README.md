# NorthAx — Android

Kotlin/Jetpack Compose port of the iOS app. Connects to the same FastAPI
backend (`backend/`) with the same API contract, auth flow, and screens.

## Stack

- Kotlin 2.2 · Jetpack Compose (Material 3 base, custom "Instrument" theme)
- OkHttp + kotlinx-serialization API client (bearer injection, single-flight
  refresh-and-retry on 401, SSE coach stream)
- EncryptedSharedPreferences for the JWT pair (Keychain equivalent)
- MVVM: `AthleteStore` / `AuthService` ViewModels mirror the iOS stores
- Navigation Compose (Settings stack) + custom tab bar; modal bottom sheets
  stand in for iOS sheets
- Canvas-drawn charts (metric trends, fitness/fatigue, effort graph, streams)

## Build & run

```bash
cd android
./gradlew :app:assembleDebug        # build the debug APK
./gradlew :app:testDebugUnitTest    # run unit tests
./gradlew :app:installDebug         # install on a connected device/emulator
```

Requires JDK 17+ (Android Studio's JBR works:
`export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"`)
and an Android SDK with platform 36 (`local.properties` → `sdk.dir`).

## Backend URL

- **debug** defaults to `http://rafaelpereira.local:8080/v1` — note that
  Android generally does **not** resolve `.local` mDNS names; set an explicit
  address in `gradle.properties`:
  - emulator → `northax.apiBaseUrl=http://10.0.2.2:8080/v1`
  - physical device → `northax.apiBaseUrl=http://<pi-ip>:8080/v1` (or the
    Tailscale HTTPS name)
- **release** defaults to `https://api.northax.app/v1`.

Debug builds allow cleartext HTTP (the Pi has no TLS); release is HTTPS-only.

## Known gaps vs iOS

- No Apple Health / HealthKit equivalent — metric sources on Android are
  intervals.icu and manual entry (no Health Connect integration yet).
- Launcher icon is a placeholder vector (no exported artwork in the repo).
- Goal target dates use a ±1-week stepper instead of a platform date picker.
- The Coach tab exists but is hidden, matching current iOS behavior.
