# History counts waiting sessions it can't read, and brings them back after an update

Settled on 2026-11-14 by the owner (issue #87, a picker: "Add to the count").

A finished session waits in the outbox while History can't save it (ADR 0007). If this version can't read a waiting
session's file, because a newer TestFlight build wrote it or the format broke, the file is moved aside so it can't
hold back the others. Those sessions now count in History's existing line, "N sessions couldn't be shown. Try
updating Pianism.", along with saved sessions it can't show (ADR 0006). There's no separate notice.

Every time the outbox is read, it first tries the files set aside again. A file it can now read, as after an update,
goes back to waiting, so it shows in History and stops being counted. It's saved with the other waiting sessions,
the next time one is. If the same session is waiting again by then, the newer copy stays and the old one is dropped.

**Why:** updating is the fix for both kinds, so one line says it. Without the retry, the line could never clear,
even after the update it asks for.

**Accepted:**
- A session hit by a format bug stays counted until a version that can read it comes out, and the line doesn't say
  which kind each counted session is.
- While History can't load at all, nothing is counted: its "couldn't load" notice shows instead.
- After a downgrade, a session a newer version saved but couldn't take out of the outbox counts twice, once of
  each kind, until the update.
