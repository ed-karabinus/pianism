# A session not saved says so

Settled on 2026-11-10, the owner's pick, from a TestFlight tester's note that a session vanishing without a word looks
like the app glitched.

When a session ends too short to be practice, it isn't saved, and Practice says why: a piano's with under a minute
played, "Not saved: under a minute of playing", and a tapped one under 10 s, "Not saved: under 10 seconds". It says it
twice over: a pop-up at the top of Practice for 4 seconds, which VoiceOver reads out, and the same words in the line
under Start, until the next session starts. Each session not saved gets its own pop-up, even after one for the same
reason.

This replaces SES-1's "dropped quietly" (the spec's SES-1 row was changed the same day, with the owner's approval) and
MIDI-1's "Too short to save".

**Why:** someone who taps Start and Stop by mistake, or plays a few notes and walks away, otherwise finds nothing in
History and thinks it was lost. The line stays because a piano's session often ends after a silence, when nobody is
looking at the screen, so a pop-up alone would be missed.
