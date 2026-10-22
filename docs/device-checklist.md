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
| 1 | **The CloudKit schema matches before the deploy:** the steps in [ADR 0008](adr/0008-icloud-sync-environments-and-deploy.md), from creating the schema on `Sync S1` to the export matching `docs/cloudkit/schema-v1-fields.txt` | Done 2026-10-21, on the owner's iPhone (simulators hit "Failed user key sync"). Steps 3–4: after #100 encrypted tag names and composers, the export matched exactly; the owner signed off on #15. Step 5: his iPhone and his Mac ("Designed for iPad") synced every field the app can set, both ways, and the export was unchanged. Step 6: deployed; Production's export equals Development's and is kept as `docs/cloudkit/schema-v1.ckdb`. |
| 2 | **iCloud's pushes reach an open app:** with a session running and its tag picker open on the owner's iPhone, add a piece on another device signed into the same account; it shows in the picker within a minute, with no relaunch. Simulators get no CloudKit pushes, so this needs a real device; the end-to-end test `testChangesFromAnotherDeviceShowWhileOpen` covers the rest, from a save to the store to the screens | 2026-10-22, owner's iPhone and Mac ("Designed for iPad"), Release on Production: passed. Two of three pieces added on the Mac showed in the open picker within seconds; the first only when the app returned to the foreground (Apple may delay these low-priority pushes, so the app also fetches on return). A piece added on the iPhone showed on the Mac within seconds, and deletes and archives showed live both ways. |
| 3 | **Account changes while the app is open:** on the owner's iPhone, in a Debug build with `PIANISM_SYNC=1` and History open (simulators hit Apple's "Failed user key sync" bug), (a) turn iCloud off for Pianism in Settings: the not-syncing notice shows, with no relaunch; (b) turn it back on: the notice goes; (c) sign out of iCloud: the notice shows, and note what history is left; (d) sign in again: note what comes back. If (a) shows no notice, iCloud reports the account as available with Pianism's switch off, and that needs a follow-up issue | 2026-10-21, owner's iPhone: (a) passed, and iOS removed the synced history from the device; it offered no "keep on iPhone". Turning the switch off ends the app, and opening it from the app switcher drops launch variables, so relaunch with `devicectl`. (b) passed: the notice went and the history came back at once. (c) and (d) not run. |

**Why these are manual:** they need an iCloud account, and CI never uses the owner's (E4). Test
simulators must stay signed out of iCloud: the end-to-end test `testHistorySaysWhenICloudIsntSyncing`
fails on one that's signed in. The two that check sync, `Sync S1` and `Sync S2`, are never picked by
`scripts/simulator-destination.sh`.

On the Mac, run Release only after clearing a Debug run's data: the two builds share one local store,
and on 2026-10-22 Release uploaded a Debug run's test data to Production, which the owner deleted.
