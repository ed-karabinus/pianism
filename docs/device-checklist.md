# Device checklist

Checks that need real hardware, so CI can't run them (CLAUDE.md, workflow rule 8). The owner runs
them before each milestone tag and on any new piano or iOS version. Each entry says why it can't be
automated and which automated test covers part of it.

Recordings live in `~/Developer/pianism-recordings/` until MIDI-1 turns them into test fixtures.

## Kawai CA59 (issue #20)

| # | Check | Expected | Last run |
| --- | --- | --- | --- |
| 1 | Bluetooth MIDI: pair "CA59 Bluetooth", then play notes and use the sustain pedal | Notes arrive with real note-offs; the pedal sends CC64 about every 12 ms while it moves; nothing arrives while idle (no Active Sensing). One Bluetooth host at a time. | 2026-10-15, Mac and iPhone: as expected |
| 2 | USB MIDI: connect the piano's USB to Host port (rear panel, type B) to the iPhone, with Bluetooth MIDI off | The piano appears as "MIDI KEYBOARD" with no prompt on iPhone (the Mac asks "Allow accessory to connect?"). Same messages as Bluetooth, one per packet. | 2026-10-16: as expected |
| 3 | USB while Bluetooth MIDI is connected | USB sends nothing until Bluetooth MIDI is off | 2026-10-16: as expected |
| 4 | Unplug and replug USB at the piano's end, without playing | CoreMIDI reports the source removed, then added, within a millisecond. Nothing is sent until a key is played; notes played while unplugged are never sent. | 2026-10-17: as expected |
| 5 | Restart the piano while USB is connected | Bluetooth MIDI switches back on, and USB stays connected but silent until it's off again | 2026-10-17: as expected |
| 6 | Auto power-off: leave the piano idle until it switches itself off | Not yet known | Skipped 2026-10-17: the owner thinks it never switches off |

**Why these are manual:** they depend on the piano's firmware and on iOS's MIDI stack, which no
simulator or CI runner provides. **What's automated instead:** once MIDI-1 lands, the recordings
from these checks replay through the MIDI adapter as fixtures, so the behaviour above is tested on
every PR. A change in behaviour on a new firmware or iOS version still needs this checklist.
