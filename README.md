# FieldLog Mobile

Flutter app for offline-first scientific field data collection. It stores work on
the device and syncs submissions to the FieldLog backend when connectivity is
available.

## Requirements

- Flutter 3.38.7 (CI uses this version)
- Android SDK for Android builds
- Xcode on macOS for iOS builds
- A reachable FieldLog API and PowerSync service

The app source is now maintained in this repository. Backend services and their
deployment remain in [field-log-poc](https://github.com/The-Field-Company/field-log-poc).

## Configure and run

Create a local config from the example and set URLs reachable from your device:

```bash
cp .env.json.example .env.json
flutter pub get
flutter run --dart-define-from-file=.env.json
```

`.env.json` is ignored by Git. Do not commit local environment configuration.
In debug builds, the app's Settings screen can also override the service URLs.

For a USB-connected Android device, enable USB debugging and run:

```bash
adb reverse tcp:8000 tcp:8000
flutter run --dart-define-from-file=.env.json -d <device-id>
```

For the Android emulator, use `10.0.2.2` to reach services running on the host;
the example config contains these defaults.

## Docker

Run the app on an Android emulator in Docker and drive it from a browser, with
the app built and installed by a matching Flutter container:

```bash
cp .env.json.example .env.json   # use http://10.0.2.2:<port> URLs
docker compose up -d
```

The `android-emulator` service runs the [budtmo/docker-android](https://github.com/budtmo/docker-android)
emulator (Android 14 / API 34) with its built-in noVNC web UI. Open
**http://stacey:6080** in a browser to see and control the emulator — no
separate screen-cast client is needed. The `flutter-run` service connects over
ADB, waits for boot, then `flutter run`s the app onto it.

The emulator forwards the backend ports so the app's `10.0.2.2` URLs reach
services running on the host.

Requirements:

- Linux with a working `/dev/kvm` (the emulator needs KVM; Docker Desktop on
  macOS/Windows does not expose it). If the `kvm` group differs from `992`,
  set `KVM_GID`.
- ~4 GB free disk for the pre-built emulator image.

Configurable via environment variables: `KVM_GID` (host `kvm` group id) and
`BACKEND_PORTS` (space-separated list of host ports to forward, default
`8000 8080 8090`).

## GitHub Actions

Android branch builds and tagged releases use repository Actions secrets:

- `SERVER_URL`
- `POWERSYNC_URL`
- `GLITCHTIP_DSN`
- `KEYSTORE_BASE64`
- `KEYSTORE_PASSWORD`

These secrets do not transfer when source code is moved between GitHub
repositories. Add them in this repository's **Settings → Secrets and variables
→ Actions** before expecting the existing workflows to build successfully.
The keystore must be the same signing key used for existing FieldLog Android
installs so users can install updates over them.

Push a `v*` tag to build and publish a signed APK release. Branch builds are
available as Actions artifacts and expire after 30 days.

## Local Android release build

The release build needs `android/key.properties` and
`android/fieldlog-release.jks`, which must not be committed. Configure the
keystore and the three service values, then run:

```bash
flutter build apk --release --dart-define-from-file=.env.json
```

## F-Droid

F-Droid builds must be built from a public source tag. Their build metadata is
maintained in the separate `fdroiddata` repository and must supply the fixed
FieldLog API and PowerSync URLs as build-time values. These URLs are public
configuration compiled into the app; GitHub Actions secrets are not available
to F-Droid builds. Do not pass `GLITCHTIP_DSN` in the F-Droid build.

F-Droid builds one APK per ABI. Their version codes are the `pubspec.yaml`
build number × 10 + ABI (armeabi-v7a 1, arm64-v8a 2, x86_64 3), set in
`android/app/build.gradle.kts`; universal APKs keep the plain build number.
Add `fastlane/metadata/android/en-US/changelogs/` files named after the three
split version codes, e.g. `31.txt`, `32.txt` and `33.txt` for build number 3.

The F-Droid build produces an unsigned APK for F-Droid to sign:

```bash
flutter build apk --release \
  --android-project-arg=fdroid=true \
  --dart-define=SERVER_URL=https://fieldlog.thefieldco.com \
  --dart-define=POWERSYNC_URL=https://fieldlog.thefieldco.com/powersync
```

The Android application ID is `com.thefieldco.fieldlog`. APKs built before this
change used `com.fieldlog.fieldlog_mobile`; Android treats the two as separate
apps, so existing installs must be replaced rather than updated in place.

The GitHub release workflow continues to sign its APK with the project's
release key. F-Droid signs its APK with its own key, so an installation from
one channel cannot be updated directly by the other channel unless upstream
signature reproducibility is configured.
