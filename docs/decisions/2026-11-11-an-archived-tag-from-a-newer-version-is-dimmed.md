# An archived tag from a newer version is dimmed in the tag picker

Settled on 2026-11-11, the owner's pick (#132).

When a newer version of Pianism has archived a piece or skill, an older version finds it in a search as before, but
dimmed, with "Archived by a newer version of Pianism. Update to use it." under its name. Tapping it does nothing: the
session isn't tagged, and no error shows. One already on the session can still be taken off.

**Why:** the older version can read the newer one's record but not change it (ADR 0006), so it can't bring the tag back,
which choosing an archived tag does. Before, it showed "Couldn't change your tags" and tagged the session anyway, so
what you saw didn't match what happened. It can't happen until a second version exists and two devices run
different ones.
