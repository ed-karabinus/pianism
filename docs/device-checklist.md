# Device checklist

Checks that need a real piano or an iCloud account, so CI can't run them (CLAUDE.md, rule 8). The
owner runs them each milestone, as the README's Testing table says. Each row gives the last result.

## Kawai CA59 (issue #20)

| # | Check | Last result |
| --- | --- | --- |
| 1 | **Bluetooth MIDI, Mac:** pair "CA59 Bluetooth" in Audio MIDI Setup, then record practice with notes, a pause and the pedal | 2026-10-15: each note-on had a real note-off (`0x8n`). The pedal sent CC64 in-between values about every 12 ms while it moved. Nothing arrived while idle: no Active Sensing or clock. Some packets carried several messages. |
| 2 | **Bluetooth MIDI, iPhone:** pair from GarageBand (Settings → Advanced → Bluetooth MIDI Devices), then play | 2026-10-15: GarageBand received the notes. The piano connects to one host at a time, so the Mac had to disconnect first. |
| 3 | **USB, iPhone:** Bluetooth MIDI off and the piano off, cable from USB to Host (type B, on the jack panel) to the iPhone, piano on, then play in GarageBand | 2026-10-16: worked with no adapter and no prompt. The notes played and the pedal sustained. |
| 4 | **USB, Mac:** the same, recording on the Mac | 2026-10-16: macOS asked "Allow accessory to connect?" first. The piano appeared as "MIDI KEYBOARD", not by its model name. Messages were as over Bluetooth, nothing while idle, one message per packet. |
| 5 | **Unplug and replug, USB to the Mac,** at the piano's end: play a chord with the pedal while unplugged, plug in and wait 30 s, then unplug and plug in again without playing, then play | 2026-10-17: nothing played while unplugged was sent later. Plugging in sent nothing until a key was played. CoreMIDI reported the source removed on each unplug and added on each replug. Replugs at the laptop's end didn't register for about five minutes. |
| 6 | **Restart the piano with USB connected** | 2026-10-17: Bluetooth MIDI switched back on, and USB stayed connected but sent nothing. The owner's manual says USB is disabled while Bluetooth MIDI is connected. |
| 7 | **Auto power-off:** leave the piano idle until it switches itself off, and note the time and anything sent | Not run (2026-10-17): the owner doesn't expect this piano to switch itself off. |

**Why these are manual:** they depend on the piano and on Apple's MIDI and Bluetooth stacks, which
no simulator or CI runner has. The recordings from rows 1, 4 and 5 are kept on the owner's Mac.
Once MIDI-1 (#43) lands, they become fixtures for its detector tests, covering the messages.
Pairing, prompts, device names, the Bluetooth and USB switch, and power-off stay manual.

## iCloud sync (SYN-1, issue #15)

| # | Check | Last result |
| --- | --- | --- |
| 1 | **Test simulators stay signed out of iCloud:** in Settings on every simulator named `iPhone…` or `iPad…`, no Apple Account is signed in. The two that check sync are named `Sync S1` and `Sync S2`, which `scripts/simulator-destination.sh` never picks | Not run |
| 2 | **The CloudKit schema matches before the deploy:** the steps in [ADR 0008](adr/0008-icloud-sync-environments-and-deploy.md), from creating the schema on `Sync S1` to the export matching `docs/cloudkit/schema-v1-fields.txt` | 2026-10-20, main de616f7: every expected field matched. The only extra was Core Data's own `CD_moveReceipt` (and its `_ckAsset`) on both record types, now in the file. The owner signed off on #15. |

**Why these are manual:** they need an iCloud account, and CI never uses the owner's (E4). `simctl`
can't read whether a simulator is signed in. Once the not-syncing notice's end-to-end test lands (#15),
a signed-in test simulator fails it, and row 1 goes.
