# Google Play store listing

Text to paste into Play Console → Grow users → Store presence → Main store
listing. F-Droid reads its own text from `fastlane/metadata/android/en-US/`;
keep the two in step when features change.

Play rules for this text: no client, partner or competitor names, no
testimonials or rankings ("best", "#1"), no prices or promotions, no
keyword lists, and every feature described must be in the app.

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
FieldLog needs a FieldLog account. There is no sign-up inside the app: accounts are set up for your team. You can request one at https://fieldlog.thefieldco.com/request-access

PRIVACY
FieldLog has no ads and no analytics. Privacy policy: https://fieldlog.thefieldco.com/privacy
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
