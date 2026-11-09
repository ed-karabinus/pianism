# Analytics turned off and quickly back on

Settled on 2026-11-09, the owner's pick.

If "Share anonymous usage" is turned off and back on within the SDK's send interval (about 10 s), usage counts queued
before the off can still go out once it's on again. The app isn't changed for this; ADR 0011 now says so. Nothing goes
while analytics is off, as the privacy policy says.

**Why:** they go only with consent given again, it takes a quick off and on, and stopping it would mean reaching into
the SDK's queue for a case this rare.
