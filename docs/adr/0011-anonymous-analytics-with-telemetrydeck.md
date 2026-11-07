# 11. Anonymous, opt-out analytics with TelemetryDeck

- Status: accepted, by the owner on 2026-11-06
- Date: 2026-11-06
- Issue: #19

## Context and problem statement

The spec sets one target that Apple's dashboards can't measure: activation, 3 sessions in a new user's first 7
days, with a goal of 40%. Apple's retention figures cover only people who opted in with Apple, and nothing of
Apple's sees inside the app. The owner decided on 2026-10-18 that this blocks launch, and must be live for
TestFlight, so that feedback from testers and launch isn't guesswork.

Principle P7 is private by default: no account, and practice data stays on the device and in the person's own
iCloud. Principle E5 allows one third-party runtime dependency in v1, behind its own adapter, with an ADR the owner
approves. This is that ADR.

## Considered options

1. **TelemetryDeck.** Built for apps like this: no account for the person using the app, no IP addresses stored,
   timestamps rounded to the hour, servers in the EU, and a Swift package with no dependencies of its own. Its free
   plan is 50,000 events a month, with 3 months of data.
2. **Apple's dashboards only.** No SDK and no label change, but no activation number, which is the point.
3. **Firebase or Mixpanel.** More features, but made for following people around. They're heavier and far from P7.
4. **Our own endpoint.** No third party, but a server to run, secure and pay for, for one number.

## Decision

Option 1, decided by the owner on 2026-10-13. Its version is pinned exactly, at 2.14.2 when this was written, so a
new version arrives only by a reviewed change.

### What's sent

Decided by the owner on 2026-11-06.

| Signal | When | Extra details |
| --- | --- | --- |
| `TelemetryDeck.Session.started` (automatic) | Each time the app opens or comes back from the background | None |
| `Install.firstLaunch` | Once, on first launch, if analytics is on then | None |
| `Practice.sessionSaved` | Each time a session is saved | `source`: `timer`, `midi` or `manual` |
| `Activation.reached` | Once, on the 3rd session within 7 days of first launch | None |
| `Paywall.shown`, `Paywall.purchased`, `Paywall.restored` | From PRO-1, when the paywall exists | None |

**The SDK adds these to every signal,** and we found no setting to remove them: a hash of an ID for this install, a
session ID, device model and architecture, OS and version, screen size and orientation, app version and build,
language, region, time zone, color scheme, layout direction, text size, bold text, and whether it's an App Store,
TestFlight, debug or simulator build.

A new signal, or a new detail on one, needs this list changed first.

### What's never sent

Practice content of any kind: piece names, skill names, tags, notes, session times or lengths, goals, the number of
sessions beyond the signals above, the piano's name, and anything else a person typed. Also no name, email, Apple ID
or iCloud identifier. `source` is the only value we attach, and it comes from a fixed list, never from a person.

### What counts as activation

Any saved session counts: timer, piano or added by hand, saved within 7 days of first launch. Logging practice is
what the app is for, so someone who logs by hand is using it. A session deleted later still counted. So someone adding
three old sessions in one sitting activates, which we accept.

Activation is a ratio of two signals, `Activation.reached` over `Install.firstLaunch`. If analytics was off at first
launch, neither is sent, even if it's turned on later, so the ratio stays honest. A reinstall can count as a new
user, and so can a new device that already has history in iCloud, as nothing ties them together, by design.

### The identifier

The SDK's default: a salted hash of the system's per-vendor install ID. It lets us count active people and follow a
funnel, without being able to tell who anyone is. We also considered sending one same ID from everyone, which removes
Device ID from the label but leaves no count of active people. The owner chose the per-install hash on 2026-11-06.

The SDK's session statistics are turned off (`sessionStatsEnabled = false`), since they send more than this list, such
as an automatic new-install signal with its date. `Install.firstLaunch` does that job.

### The opt-out

- **Settings has a switch, on by default,** with a line under it saying what's sent and what's never sent.
- **There's no prompt, and the welcome screen doesn't mention it.** People are told by that switch, the App Store
  privacy label and the privacy policy. TelemetryDeck's position is that an opt-out isn't legally required, as what it
  stores isn't personal data. We offer one anyway, because of P7.
- **Off means nothing further goes out.** The SDK's own `analyticsDisabled` isn't enough: it stops new signals, but its
  send loop doesn't check it, so signals already queued still go, within 10 s by default. And it can't safely be shut
  down: `TelemetryDeck.terminate()` leaves scheduled work behind that calls its shared manager, which traps in Debug
  and, in Release, makes a new one with no App ID. So the adapter never starts the SDK while analytics is off, and
  turning it off sets `analyticsDisabled` and swaps in a network that discards everything, which empties the queue
  without anything leaving. Adapter tests prove this against a fake network, since it's the promise the switch makes.
  (Amended 2026-11-06, while building: this first said to use `terminate()`, which a test showed to be unsafe.)
- **Turning it back on** can send only what the SDK saved to disk just before the app last left the screen, if it had
  no chance to discard it. What was queued while the app stayed open is gone.

### Which builds send

Only Release builds with an App ID: App Store and TestFlight, which the SDK marks apart, and the owner's own Release
installs, whose switch the owner can turn off. Debug builds, simulators, tests and CI never start the SDK, so they can't pollute the
numbers or reach the network.

**The App ID stays out of this public repository.** It's in the shipped app, but publishing it would make it trivial
for anyone to send fake signals and use up the monthly allowance. It lives in the owner's git-ignored
`Config/Local.xcconfig`. With no App ID, the adapter does nothing, so a build without one is silent rather than
broken. The submission checklist gains a check that a TestFlight build's signals reach the dashboard.

### How it's built

- **The core gets an `Analytics` port** and the rule for when activation is reached, both tested on Linux with a
  recording fake. Nothing outside the adapter sees TelemetryDeck's types.
- **A new `PianismAnalytics` package holds the adapter,** and is the only package that depends on the SDK. So the core,
  features and other adapters stay free of it, and removing it means deleting one package.
- **`App/PianismApp.swift` wires it in,** as with every other adapter. It reads the App ID from `Info.plist`, which
  only Release fills in, so the Debug path through the same code finds none and uses the port's do-nothing version.

### The privacy label and manifest

As TelemetryDeck's guide says, and as the manifest inside the SDK declares: **Device ID** and **Product Interaction**,
both for analytics, both not linked to the person, and neither used for tracking. So the App Store no longer says
"Data Not Collected". `App/PrivacyInfo.xcprivacy` declares the same, and the label itself is entered in App Store
Connect with #56. The privacy policy, which the website doesn't have yet, has to say the same before submission.

## Consequences

- We can read activation, and see roughly how many people use the app and how they record, including how many use a
  piano.
- The App Store page shows two data types, not linked, where it would have said "Data Not Collected". That's the real
  cost, for an app that sells on being private.
- Every signal carries device details we don't need, because the SDK adds them. They're listed above, and the policy
  will say so.
- The app makes one more kind of network call, as P7 already allows. E8's "nothing leaves the device except through
  Apple" concerns logs and crash reports, and stays true of those.
- `make test-adapters`, and so CI, now fetches a package from GitHub. The SDK's own code has compiler warnings, so
  `scripts/fail-on-warnings.sh` skips third-party checkouts. Warnings in our own code still fail.
- The free plan should hold for launch: at 1,000 downloads in 90 days, our rough estimate is well under its 50,000
  events a month. Past the limit, new events stop until the month resets, and TelemetryDeck says it may move an
  account to a bigger plan after two months over. Its 3 months of data is enough to read activation weekly.
- A rename of a signal splits its history on the dashboard, so these names are worth keeping.
