# Practice offers to reconnect a Bluetooth piano

Settled on 2026-11-11, the owner's picks, following their pick of 2026-11-07 (a one-tap Reconnect if iOS 27.2 didn't
fix it, which device check P5 showed it didn't).

Pianism remembers the piano that shows up while Apple's pairing screen is open in Pianism, the last one if several.
While no piano is connected, Practice says "CA59 Bluetooth isn't connected" under the time, with a Reconnect button,
and Connect a piano says the same in its Connected section, with Reconnect and Forget This Piano. Reconnect opens
Apple's pairing screen, searching afresh; on Practice it's a sheet with a Done button, and it closes by itself once a
piano connects. In Connect a piano, Reconnect goes away as the piano connects, which takes Apple's screen with it. Forget stops both until a piano is paired in Pianism again. Any connected piano, such as the same one
over USB, hides the offer.

**Limit:** CoreMIDI doesn't say which pianos are Bluetooth ones, so a piano paired in another app, such as GarageBand,
or in iOS Settings is never remembered, and Pianism offers nothing for it. Pairing it once from Connect a piano fixes
that. The other way round, a USB piano plugged in while Apple's screen is open is remembered as the Bluetooth one, until
it's forgotten or another piano is paired there.

**Why:** iOS doesn't reconnect a Bluetooth MIDI piano after it restarts (P5, on iOS 27.0.1 and 27.2), and a CoreBluetooth
reconnect, tried on 2026-11-07, connected without CoreMIDI ever hearing the piano. A piano switches off after most
practice, so without this a Bluetooth piano's notes would start nothing until it was paired again, and Practice would
show nothing about it. Forget is there for a piano sold or now used over USB, as the line would otherwise show
whenever it's off.
