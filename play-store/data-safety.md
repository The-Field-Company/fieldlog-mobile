# Google Play Data safety answers

Answers for Play Console → Policy → App content → Data safety, worked out
from the app code at v1.0.4. Re-check them whenever the app starts sending
new data.

## What the app sends and where

| Data | When | Sent to | Code |
|---|---|---|---|
| Username and password | Sign in | FieldLog API (`/api/token/`) | `lib/services/auth_service.dart` |
| Username | Stamped on every submission as `submitted_by` | FieldLog API | `lib/screens/form_screen.dart` |
| Form answers and tally counts | On submit, uploaded when online | FieldLog API | `lib/services/powersync_connector.dart` |
| Photos (camera or gallery) | Only in sessions with a photo field | FieldLog file storage (presigned upload) | `lib/widgets/field_widgets/file_field_widget.dart` |
| Latitude, longitude, accuracy | Only in sessions with location tracking on; submitting still works without it | Inside the submission (`_location`) | `lib/screens/form_screen.dart`, `MainActivity.kt` |

All services are run by The Field Company. No analytics, ads or third-party
SDKs receive data. Production traffic is HTTPS only
(`android/app/src/main/res/xml/network_security_config.xml` allows cleartext
only to `localhost` and `10.0.2.2`).

## Data collection and security

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | Yes |
| Is all of the user data collected by your app encrypted in transit? | Yes |
| Which methods of account creation does your app support? | Username and password. Accounts are made by The Field Company, but the store listing links to the request-access page, so declare it |
| Delete account URL | https://fieldlog.thefieldco.com/privacy#delete-account (requests by email to engineering@thefieldco.com) |
| Can users request that some or all of their data be deleted without deleting their account? | Yes, by email to engineering@thefieldco.com |

## Data types

Shared: **No** for every type. Data only goes to The Field Company's own
services. Processed ephemerally: **No** for every type.

| Category → type | Collected | Required or optional | Purposes |
|---|---|---|---|
| Location → Precise location | Yes | Optional | App functionality |
| Location → Approximate location | Yes | Optional | App functionality |
| Personal info → User IDs | Yes | Required | App functionality, Account management |
| Photos and videos → Photos | Yes | Optional | App functionality |
| App activity → Other user-generated content | Yes | Required | App functionality |

Approximate location is declared because the app also asks for
`ACCESS_COARSE_LOCATION`: a user who grants only approximate location
sends approximate coordinates.

Not collected: name, email address, phone number, contacts, messages, audio,
files and docs, calendar, health, financial info, web browsing, installed
apps, device or other IDs.

## Check before submitting

- The app has no screen to turn on diagnostics, so it never sends error
  reports or performance data, whether or not the build has
  `GLITCHTIP_DSN`. If a diagnostics switch comes back, add "Crash logs" and
  "Diagnostics" (optional, Analytics) under App info and performance.
- The privacy policy at https://fieldlog.thefieldco.com/privacy must
  describe the same data. It is linked from the login and home screens.
