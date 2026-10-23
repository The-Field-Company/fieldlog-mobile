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

The F-Droid build produces an unsigned APK for F-Droid to sign:

```bash
# Replace these examples with the fixed production endpoints.
SERVER_URL='https://api.example.org'
POWERSYNC_URL='https://sync.example.org'

flutter build apk --release \
  --android-project-arg=fdroid=true \
  --dart-define="SERVER_URL=$SERVER_URL" \
  --dart-define="POWERSYNC_URL=$POWERSYNC_URL"
```

The GitHub release workflow continues to sign its APK with the project's
release key. F-Droid signs its APK with its own key, so an installation from
one channel cannot be updated directly by the other channel unless upstream
signature reproducibility is configured.
