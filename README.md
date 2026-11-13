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

The same tag also builds the Google Play bundle, which needs four more
secrets (see [Google Play](#google-play)):

- `UPLOAD_KEYSTORE_BASE64`
- `UPLOAD_KEYSTORE_PASSWORD`
- `UPLOAD_KEY_ALIAS`
- `UPLOAD_KEY_PASSWORD`

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

## Google Play

Google Play takes an Android App Bundle (AAB) signed with an upload key;
Google then signs the APKs it delivers with the app signing key held by Play
App Signing. The upload key is separate from the release key above and must
never be committed.

Create the upload key once, outside the repository:

```bash
keytool -genkeypair -v -keystore upload-keystore.jks -storetype PKCS12 \
  -alias upload -keyalg RSA -keysize 4096 -validity 10000
base64 -i upload-keystore.jks | pbcopy
```

Store the copied value as `UPLOAD_KEYSTORE_BASE64`, plus
`UPLOAD_KEYSTORE_PASSWORD`, `UPLOAD_KEY_ALIAS` (`upload`) and
`UPLOAD_KEY_PASSWORD`. Use letters and digits only in the passwords, because
they are written into a Java properties file. Keep a backup of the keystore
and passwords outside this repository.

Pushing a `v*` tag runs `.github/workflows/release-play.yml`. It fails before
building if the tag does not match the `pubspec.yaml` version or a secret is
missing, and after building if the bundle is not signed with the upload key
or its version code differs from the `pubspec.yaml` build number. The bundle
is kept as an Actions artifact for 90 days; download it and upload it in Play
Console.

Unlike the F-Droid split APKs, the bundle's version code is the plain
`pubspec.yaml` build number. Play requires every upload to have a higher
version code than the last one.

Store listing text, graphics and Data safety answers are in `play-store/`.
F-Droid does not read that folder.

F-Droid installs are always signed with F-Droid's key. The Play app signing
key is chosen when the app is first set up in Play Console: if it is the
release key above, GitHub installs can update from Play; otherwise they
cannot. Users moving between differently signed builds must uninstall first,
which deletes records that have not synced yet.
