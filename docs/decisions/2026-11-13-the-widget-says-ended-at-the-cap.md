# The widget says "Ended" once a session reaches the cap

Settled on 2026-11-13: the owner asked for the fix before release (device check W9); the word is the Live
Activity's.

When a timer session reaches the cap with the app closed, the widget's title changes from "Practicing" to "Ended",
the word the Live Activity already uses then, above the day's total stopped at the cap. As before, while a session
is stored the widget has no Start; it comes back once the app runs and saves the session. A session that ended
itself before midnight and isn't saved yet shows "Ended" above 0:00 the next day, as the activity still says
"Ended" too.

**Why:** "Practicing" above a clock that had stopped looked broken next to the activity's "Ended", and the owner
wants the app to look clean.
