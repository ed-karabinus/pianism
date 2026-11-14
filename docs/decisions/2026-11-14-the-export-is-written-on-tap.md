# Export writes the file on tap, then shares it

Settled on 2026-11-14 by the owner (device check S11, after trying it on the iPhone: "that approach is def the
winner").

Tapping Export sessions writes "Pianism sessions.csv" first, then opens the share sheet with that file. The file
holds history as it is at the tap.

**Why:** each of the earlier ways cost something.
- **Shared as data:** AirDrop renamed it "comma-separated values-….csv" (S10, 2026-11-13).
- **Shared as a file made when the sheet asked for it (#253):** the sheet waited 2 s, as iOS tried to open the file
  in place, and AirDrop sent it as text, "text-….txt" (S11).

A file written first opens at once and keeps its name and type everywhere tried: AirDrop, a draft message and Save to
Files.

**If the file can't be written,** an alert, "Couldn't export your sessions", says why, as Apple's apps do when an
action fails (the owner's pick, 2026-11-14). A full device says "There isn't enough storage on this device. Free up some
space, then try again.", as Camera and Photos name a full device; anything else says "Pianism couldn't reach its
storage. Try again in a moment.", as other failed saves do. There's no button to iPhone Storage, as the only link to it
is private.

**Accepted:** the history is read before the sheet opens, on the tap. That's quick at today's sizes, though not measured. Each
export leaves a copy in the app's temporary folder, which iOS clears.
