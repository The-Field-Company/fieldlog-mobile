# Google Play store listing

Text to paste into Play Console → Grow users → Store presence → Main store
listing. F-Droid reads its own text from `fastlane/metadata/android/en-US/`;
keep the two in step when features change.

Play rules for this text: no client, partner or competitor names, no
testimonials or rankings ("best", "#1"), no prices or promotions, no
keyword lists, and every feature described must be in the app.

## App name (max 30 characters)

```
FieldLog: Offline Field Data
```

## Short description (max 80 characters)

```
Record wildlife sightings, patrols and surveys in the field, even with no signal
```

## Full description (max 4000 characters)

```
FieldLog is a data collection app for teams who work outdoors: rangers, ecologists, monitors and survey crews. Record what you see on the ground, with or without a signal. Your records are saved on your phone first and upload by themselves when you are back in coverage.

WORKS WITHOUT SIGNAL
• Every record is saved on the phone the moment you submit it
• Uploads start automatically when a connection returns, including photos
• An Online / Offline badge shows your connection at a glance
• After each submission FieldLog tells you whether it was uploaded or saved on the phone to upload later

FORMS BUILT FOR YOUR WORK
Your team sets up each session, and FieldLog shows it as a clear, step-by-step form:
• Text, numbers, dates and times
• Dropdowns, checkboxes, radio buttons and switches
• Sliders, star ratings, tags, rankings and matrices
• Multi-page forms for longer surveys
• Photo fields that use the camera or your gallery

FAST TALLY COUNTS
For counts, a session can use a tally board instead of a form:
• Picture buttons grouped into folders, such as antelope or predators
• Tap once per animal or sign observed
• Running totals on every button

LOCATION WHEN A SESSION NEEDS IT
Sessions that record location add your GPS position to each record. Location is only requested for those sessions, and you can still submit if you turn it off. FieldLog does not track your location in the background.

JOIN YOUR TEAM
Open an invite link from your team to join a private session, or browse public sessions and join them from the app.

ACCOUNTS
You need a FieldLog account to sign in. Accounts are set up for your team, and there is no sign-up inside the app. Request one at https://fieldlog.thefieldco.com/request-access

PRIVACY
No ads and no analytics. FieldLog does not send diagnostics from your phone. Privacy policy: https://fieldlog.thefieldco.com/privacy
```

## What's new (first release, max 500 characters)

```
First release on Google Play. Record forms and tally counts offline, with automatic upload when you are back in signal.
```

## Other store settings

| Setting | Value |
|---|---|
| App or game | App |
| Free or paid | Free |
| Category | Productivity |
| Tags | Pick from Play's list: Productivity, Tools, Science (only those that apply) |
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

Upload the screenshots in this order:

| File | Shows |
|---|---|
| `1.png` | Sign-in screen |
| `2.png` | Home screen with sessions and the Online badge |
| `3.png` | Tally board with picture buttons and running totals |
| `4.png` | Multi-page form, page 1: choices, dropdowns and a switch |
| `5.png` | Multi-page form, page 2: star rating, slider and photo field |
| `6.png` | Patrol report with date picker, dropdowns and radio buttons |
| `7.png` | Offline: "Saved locally, will upload when online" |

They are 1116 × 2231 with no alpha: the phone status bar is cropped off and
18 px of white is added to each side, so they fit Play's 2:1 limit.

## App access (for Google's reviewers)

Play Console → Policy → App content → App access → "All or some
functionality is restricted". Give the username and password of a dedicated
review account (not a staff or admin account) that is subscribed to a demo
session, and add:

```
Sign in with the details above. The account is subscribed to a demo session with sample data. Open the session from the home screen to see the form and submit a test observation. Location access is optional.
```
