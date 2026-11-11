# App Store Connect

What's set up in App Store Connect, and when. Only the owner makes changes there, as only the owner uploads and
submits (`docs/decisions.md`, 2026-10-15). Update this file when something changes. No email addresses or
account details go here.

## Agreements

| Item | Value | Set |
| --- | --- | --- |
| Paid Apps agreement, tax and banking | Active | 2026-10-16 |

## The app

| Item | Value | Set |
| --- | --- | --- |
| Price | Free, base country United States | 2026-11-07 |
| Availability | 144 of 175 storefronts: all but the EU's 27, Iceland, Norway, Switzerland and the UK, as `docs/decisions.md` decides (2026-11-07). Liechtenstein has no storefront of its own | 2026-11-07 |

## The listing (English, U.S.), to enter (#56)

Settled with the owner on 2026-11-08, not entered yet. Fill in each "Set" date once it's in App Store Connect. Words
in the name and subtitle count as search keywords, so the keywords don't repeat them. Every line must be true in the
build that's submitted, and the auto-start always says "while Pianism is open" (CLAUDE.md).

| Item | Value | Set |
| --- | --- | --- |
| Name (30) | Pianism: Practice Tracker | |
| Subtitle (30) | Time it with a tap or a piano | |
| Keywords (100) | `log,timer,midi,keyboard,lessons,music,student,teacher,scales,sight reading,repertoire,habit,goal` | |
| Promotional text (170; changes need no review) | Below | |
| Description (4,000) | Below | |
| Support URL | https://ed-karabinus.github.io/pianism/ (live 2026-11-10, website PR #4) | |
| Privacy Policy URL | https://ed-karabinus.github.io/pianism/privacy/ (live 2026-11-10, website PRs #4 and #5) | |

Promotional text:

> Set a weekly goal, time each session with a tap and watch your week fill in. Got a digital piano? Connect it and
> sessions start themselves while Pianism is open.

Description:

```text
Pianism keeps track of your piano practice, so you can see your week build up.

TIME IT WITH ONE TAP
Start a session, pause when the phone rings, stop when you're done. Pianism counts the time you practiced, not the breaks.

YOUR PIANO STARTS THE TIMER
Connect a digital piano over Bluetooth or USB, and sessions start, pause and save themselves while Pianism is open. The first 5 piano sessions are free, then it's part of Pianism Pro.

TAG PIECES AND SKILLS
Note what you worked on: a Chopin nocturne, scales, sight-reading. Add a composer and a target tempo to each piece.

A WEEKLY GOAL THAT FITS YOU
Set how many days a week you want to practice, watch the week fill in, and get a reminder on days you haven't practiced yet.

EVERY SESSION, DAY BY DAY
History lists every session, with a widget for your home screen and your sessions synced through iCloud to your other devices.

PIANISM PRO
One purchase, no subscription:
• Piano sessions start, pause and save themselves while Pianism is open, after the first 5
• Time per piece and skill: total, last 30 days, and time playing and paused
• Export every session as a CSV file, for Numbers or Excel

No account, no ads. Your practice stays in your iCloud.
```

## Pianism Pro, the in-app purchase (#52, ADR 0012)

| Item | Value | Set |
| --- | --- | --- |
| Type | Non-Consumable | 2026-11-07 |
| Reference name | Pianism Pro | 2026-11-07 |
| Product ID | `com.edkarabinus.Pianism.pro`. Permanent: App Store Connect can't change it or reuse it, and it must match `ProProduct.id` | 2026-11-07 |
| Availability | The same 144 as the app | 2026-11-07 |
| Price | $9.99 until 31 January 2027, then $14.99, base country United States, as a temporary price change (#52; S1 in `docs/device-checklist.md` checks it, once #207 merges) | 2026-11-07 |
| Family Sharing | Off. Turning it on can't be undone; whether to is still to decide (D10 in `docs/plans/plan-pro.md`) | 2026-11-07 |
| Display name (English, U.S.) | Pianism Pro | 2026-11-07 |
| Description (English, U.S.) | "MIDI auto-start while Pianism is open, stats and export" (55 characters, the limit) | 2026-11-07 |
| Review screenshot | The Pro screen on iPhone, from #208's tests ([`pr-208/pro-screen-iphone.png`](https://github.com/ed-karabinus/pianism/blob/evidence/pr-208/pro-screen-iphone.png)). It shows $14.99, the base price, which is fine: only the reviewer sees it | 2026-11-07 |
| Review notes | Below | 2026-11-07 |
| Promotional image | Not set. Only needed to promote the purchase on the App Store | |
| Status | Prepare for Submission. Apple's rule: the first non-consumable goes to review with a new app version, so it's added at submission, not before | 2026-11-07 |

Review notes, as entered:

> Pianism Pro is a one-time, non-consumable purchase with no subscription. To see it, open the Settings tab and tap
> Pianism Pro. No sign-in, account or piano is needed. Restore Purchases is on that screen and in Settings. Pro's main
> feature—sessions that start, pause and save themselves—needs a digital piano connected by USB or Bluetooth MIDI while
> Pianism is open. The rest of the app works without one.

If the Pro screen says "The price isn't available right now." with a working network, the App Store isn't offering
the product: check the status above, the product ID, and, in a Debug build, the Sandbox account (S1 in
`docs/device-checklist.md`).

## Still to do

| What | When |
| --- | --- |
| Enter the listing above | Before submission |
| Age rating, and the App Privacy answers: **Device ID** and **Product Interaction**, both for analytics, not linked to the person and not used for tracking, as ADR 0011 says and `App/PrivacyInfo.xcprivacy` declares | Before submission (#56) |
| A new review screenshot showing stats and export too | Before submission, once HIS-4 and EXP-1 ship |
| Change the description if CSV export (EXP-1) is cut | Before submission |
| Attach Pianism Pro to v1.0 on the version page, and the app's own App Review notes (no piano needed to reach Pro) | At submission (#59) |
