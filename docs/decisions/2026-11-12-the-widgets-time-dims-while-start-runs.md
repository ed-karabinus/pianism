# The widget's time dims while Start runs

Settled on 2026-11-12, the owner's pick.

After a tap on the widget's play button, its time dims until the widget shows the new session, using WidgetKit's
`invalidatableContent()`.

**Why:** Start takes 3 to 4 seconds on an iPhone, as iOS launches the app in the background first (device checks W4
and L4). With nothing changing meanwhile, the owner thought the tap hadn't registered and tapped again, which opened
the app.
