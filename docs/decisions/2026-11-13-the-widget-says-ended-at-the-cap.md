# The widget says "Ended" once a session reaches the cap, and offers Start

Settled on 2026-11-13 by the owner, in four steps:

1. Device check W9, then a picker: "Ended + Start", and a fresh day from midnight.
2. "Start + banner", over an "Ended" widget with no Start that opens the app.
3. The banner stored from the cap, and kept until "Edit or in-app Start".
4. A "Keep" button beside Edit.

The word "Ended" is the Live Activity's.

## The widget

When a timer session reaches the cap with the app closed, the widget's title changes from "Practicing" to "Ended",
above the day's total stopped at the cap, and Start shows again. Tapping it saves the capped session, ended at the
cap, then starts a new one, whether the app was suspended or not running. From midnight on, if the app still hasn't
run, the widget shows a fresh day: "Today", 0m and Start. The capped session is saved when the app next runs.

## The app's cap banner

"Pianism stopped your session at 1 hour of practice, in case the timer was left running." It has two buttons:

- **Keep:** the hour was practice; the banner goes.
- **Edit:** opens the session in History, and the banner goes.

It's stored the moment the session is capped, so it outlives any relaunch, including a background launch that iOS ends
before the app is opened. It stays until:

- Keep or Edit, or
- a Start in the open app, where the banner is there to see.

A Start with the app away, from the widget or a Lock Screen, keeps it. Once a newer session has started, the banner
reads "Pianism stopped an earlier session at 1 hour…". It sits under the new session's clock while that runs, and stays
after it ends, even when it's stopped from the Lock Screen. If the newer session reaches the cap too before the app is
opened, the banner becomes that session's.

**Why:**

- **"Ended":** "Practicing" above a clock that had stopped looked broken next to the activity's "Ended", and the owner
  wants the app to look clean. "Ended" gives a visual cue that the session ended (the owner's reason).
- **Start on the widget:** it saves a trip into the app. The owner: "I don't want a bare widget". The extra code was
  worth it.
- **A stored banner:** its Edit is the prompt to fix an hour that was really a forgotten timer, which is most likely
  just when the app stayed closed. So neither the widget's Start, nor a Lock Screen Stop, nor iOS ending the app may
  skip it.
- **Keep:** a banner that stays until it's acted on needs a way to say the hour was real.

A capped session deleted in History leaves the banner up until Keep or Edit. Edit then finds nothing to open. That's
rare enough to leave.
