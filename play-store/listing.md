# Google Play store listing

Text to paste into Play Console → Grow users → Store presence → Main store
listing. F-Droid reads its own text from `fastlane/metadata/android/en-US/`;
keep the two in step when features change.

## App name (max 30 characters)

```
FieldLog
```

## Short description (max 80 characters)

```
Offline-first field data collection for research and conservation teams
```

## Full description (max 4000 characters)

```
FieldLog is a field data collection app for research and conservation teams. Record observations on the ground, with or without a signal, and they sync to your team's FieldLog sessions when you are back online.

WORKS OFFLINE
Everything you record is saved on your phone first. When a connection returns, FieldLog uploads your submissions and photos automatically. A status indicator shows whether you are online and whether your work has been uploaded.

FORMS AND TALLY COUNTS
Each session is set up by your team with either a form or a tally board:
• Forms with text, numbers, dates and times, dropdowns, checkboxes, radio buttons, sliders, ratings, switches, tags, rankings and matrices
• Photo fields using the camera or your gallery
• Tally boards with picture buttons: tap once per animal or sign observed

LOCATION WHEN YOU NEED IT
If a session records location, FieldLog adds your GPS position to each submission. Location is only requested for those sessions, and you can still submit if you turn it off.

JOIN YOUR TEAM'S SESSIONS
Browse public sessions and join them, or open an invite link from your team to join a private one.

ACCOUNTS
FieldLog needs a FieldLog account. There is no sign-up inside the app: accounts are created by The Field Company. You can request one at https://fieldlog.thefieldco.com/request-access

PRIVACY
FieldLog has no ads and no analytics. Privacy policy: https://fieldlog.thefieldco.com/privacy
```

## Other store settings

| Setting | Value |
|---|---|
| App or game | App |
| Free or paid | Free |
| Category | Productivity |
| Contact email | engineering@thefieldco.com |
| Website | https://thefieldco.com |
| Privacy policy | https://fieldlog.thefieldco.com/privacy |
| Ads | No, the app contains no ads |

## Graphics

| Asset | File | Play requirement |
|---|---|---|
| App icon | `icon.png` | 512 × 512, 32-bit PNG with alpha |
| Feature graphic | `feature-graphic.png` | 1024 × 500, PNG without alpha |
| Phone screenshots | `screenshots/1.png` … `7.png` | 2–8, longest side at most twice the shortest, no alpha |

The screenshots were taken on a phone with the Atherstone demo sessions:
home, Game Count tally, Rhino Monitoring (two pages), Patrol report, a report
filled in offline, and the "saved locally" confirmation. The phone status bar
is cropped off and 18 px of white added to each side, so they fit Play's 2:1
limit.

## App access (for Google's reviewers)

Play Console → Policy → App content → App access → "All or some
functionality is restricted". Give the username and password of a dedicated
review account (not a staff or admin account) that is subscribed to a demo
session, and add:

```
Sign in with the details above. The account is subscribed to a demo session with sample data. Open the session from the home screen to see the form and submit a test observation. Location access is optional.
```
