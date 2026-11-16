# The island's clock may shorten to "1:00:…" beside another app

Settled on 2026-11-15 by the owner (device check L13: "it doesn't cut off but it does truncate. this is good enough I
think").

When another app's Live Activity shares the Dynamic Island, such as Music playing, iOS gives Pianism's side less room.
With a session ended at the cap, the clock then reads "1:00:…", in the island and in the small bubble beside it. Before
#256 it was cut off mid-digit, as "1:00:0". Alone in the island, the clock reads in full.

**Why:** the shortened clock still shows the hour has passed, and nothing is cut off mid-digit. How much room iOS gives
depends on the other app and on whether the session is running: with a running session beside Voice Memos, Notes or
Music, iOS showed only Pianism's icon, whatever width or font the clock had. So a change to the clock's frame can't
make it read in full every time.

**Accepted:** beside another app, the clock may lose its last digits or, with a running session, not show at all,
leaving only the icon. The Lock Screen, the widget and the app show the full time.
