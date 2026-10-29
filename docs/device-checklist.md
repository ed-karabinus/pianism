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
| 7 | **Auto power-off:** leave the piano idle until it switches itself off, and note the time and anything sent | 2026-10-18, at the 15-minute setting, over USB and then Bluetooth to the Mac: each time the piano switched itself off 904 s after the last key was released. It sent nothing first, and CoreMIDI reported the source removed. |

**Why these are manual:** they depend on the piano and on Apple's MIDI and Bluetooth stacks, which
no simulator or CI runner has. The recordings from rows 1, 4, 5 and 7 are fixtures for MIDI-1's
detector tests (`Packages/PianismCore/Tests/PianismCoreTests/Fixtures`), covering the messages.
Pairing, prompts, device names, the Bluetooth and USB switch, and power-off stay manual.

## MIDI-1 (issue #43)

Run a Debug build on the iPhone, and watch the log with
`log stream --level info --predicate 'subsystem == "com.edkarabinus.Pianism"'` (without `--level info`, the
latency line doesn't show).

| # | Check | Last result |
| --- | --- | --- |
| M1 | **USB, connected before launch:** piano on and plugged in, open Pianism, play three notes. Practice shows "Practicing" within a second, and the log line "MIDI session started … ms after its third note" reads under 250 ms (NFR-5). The adapter test `aSourceThatExistedBeforeTheAdapterIsHeard` covers the connection on the Mac; the latency needs the device | Not run yet. |
| M2 | **Bluetooth, with no pairing screen in Pianism:** pair the piano in GarageBand, quit it, open Pianism and play; then switch the piano off and on, and play again. Notes arrive both times. If the second fails, note it on #44, which adds pairing | Not run yet. |
| M3 | **Unplug and replug mid-piece, USB, at the piano's end:** the notes after the replug reach the same session. The adapter tests `aSourceThatAppearsAfterLaunchIsHeard` and `aRemovedSourceStopsNothingElse` cover it with virtual sources; this checks a real piano's endpoint | Not run yet. |
| M4 | **Lock mid-piece:** play, press the side button, wait two minutes, unlock. Practice opens on "Paused at your last note", with the time counted up to the last note and none for the two minutes. The model test `aSessionLeftForHalfAnHourEndsAfterItsLastNote` covers the rule; this checks that coming back to the app applies it | Not run yet. |
| M5 | **The drop-back:** play, then stop and watch Practice. The timer counts on past the last note, and at a minute it drops back to the last note's time and says "Paused at your last note". Note whether the drop-back reads as expected or as a glitch | Not run yet. |
| M6 | **The screen stays on:** set Auto-Lock to 30 seconds, play, then leave the iPhone alone for 11 minutes. The screen stays on through the pause, and locks about 30 s after the session saves itself. A session started by tapping Start still locks at 30 s | Not run yet. |
| M7 | **Battery:** a 30-minute MIDI session with the screen on. Note the battery percentage before and after | Not run yet. |
| M8 | **The piano playing itself:** connected, play the piano's demo song or a recording on the piano. Note whether its notes reach Pianism and start a session | Not run yet. |
| M9 | **Swiped away mid-piece:** play, open the app switcher, swipe Pianism away, wait two minutes and open it. Practice shows "Paused at your last note" with the time up to the last note. The end-to-end test `testAKillWhileAwayKeepsTheLastNote` covers going to the Home Screen. The switcher gesture isn't scripted: it's flaky, and the simulator may not kill the app the way a device does | Not run yet. |

**Why these are manual:** the simulator has no MIDI, and the Mac's virtual sources stand in for a
piano only in software. Bluetooth pairing and a real cable stay manual.

## MIDI-2 (issue #44)

Run a build on the iPhone, as for MIDI-1. The log line "Pianos heard: …" in Console shows what CoreMIDI lists.

| # | Check | Last result |
| --- | --- | --- |
| P1 | **The piano's name:** with the piano on USB, Practice says "MIDI KEYBOARD connected" (or whatever name the log shows); over Bluetooth, its Bluetooth name. Unplugged, it says "Connect a piano" within a couple of seconds. The adapter test `connectedPianosAreNamed` covers the names with virtual sources; this checks a real piano's | Not run yet. |
| P2 | **Plugged in at the iPhone's end only:** what does Practice say, and what does the log list, before the cable is replugged at the piano's end? It tells whether a hint on Practice could ever spot that case (decided with Ed, 2026-10-28: the tip goes in the pairing sheet for now) | Not run yet. |
| P3 | **The screen stays on while ready (MIDI-R5):** Auto-Lock at 30 seconds, piano connected, Practice open and no session: the screen stays on, and locks about 15 minutes after the last note (decided with Ed, 2026-10-28); note whether it locks at once then or after the 30 s. On History, it locks after 30 s. The model tests `aMIDISessionKeepsTheScreenAwakeUntilItEnds` and `aConnectedPianoKeepsTheScreenOnFifteenMinutes` cover the rule | Not run yet. |
| P4 | **Pairing from Pianism:** with Bluetooth MIDI on at the piano and no USB cable, tap the piano line on Practice, then "Pair a Bluetooth piano". iOS asks for Bluetooth with Pianism's reason; allow it. The piano shows in Apple's list; tap it to connect, go back, and the Connected section lists it, as Practice does once the sheet is closed. Play three notes: a session starts. Note how Apple's screen looks inside Pianism (title, list) | Not run yet. |
| P5 | **After the piano restarts:** paired from Pianism as in P4, switch the piano off and on with Pianism open. Note whether it comes back by itself, or only after opening the pairing screen again (M2 found it didn't after pairing in GarageBand). This decides whether #44 needs a PR that reconnects it | Not run yet. |

## Low battery (NFR-10, issue #140)

Simulators can't set a battery level, so the warning's rule has a model test (`aLowBatteryIsShownWhileTheScreenIsKeptOn`) and its reading of the battery is checked here.

| # | Check | Last result |
| --- | --- | --- |
| B1 | **The warning:** as the battery runs down, unplugged, piano on USB, Practice open, no session: the low-battery line, with a red battery icon, first shows somewhere from 24 % down to 20 % in the status bar, as iOS reports the level to apps in 5 % steps. Note the percentage it showed at. Plug in: it goes. Unplug: it's back. Unplug the piano's cable too and start a timer session: it goes, as nothing keeps the screen on then. Then, with the line showing in a MIDI session, lock the phone, plug in and unlock: the line goes | Not run yet. |

## iCloud sync (SYN-1, issue #15)

| # | Check | Last result |
| --- | --- | --- |
| 1 | **The CloudKit schema matches before the deploy:** the steps in [ADR 0008](adr/0008-icloud-sync-environments-and-deploy.md), from creating the schema on `Sync S1` to the export matching `docs/cloudkit/schema-v1-fields.txt` | Done 2026-10-21, on the owner's iPhone (simulators hit "Failed user key sync"). Steps 3–4: after #100 encrypted tag names and composers, the export matched exactly; the owner signed off on #15. Step 5: his iPhone and his Mac ("Designed for iPad") synced every field the app can set, both ways, and the export was unchanged. Step 6: deployed; Production's export equals Development's and is kept as `docs/cloudkit/schema-v1.ckdb`. |
| 2 | **iCloud's pushes reach an open app:** with a session running and its tag picker open on the owner's iPhone, add a piece on another device signed into the same account; it shows in the picker within a minute, with no relaunch. Simulators get no CloudKit pushes, so this needs a real device; the end-to-end tests `testAPieceFromAnotherDeviceShowsWhileOpen` and `testASessionFromAnotherDeviceShowsWhileOpen` cover the rest, from a save to the store to the screens | 2026-10-22, owner's iPhone and Mac ("Designed for iPad"), Release on Production: passed. Two of three pieces added on the Mac showed in the open picker within seconds; the first only when the app returned to the foreground (Apple may delay these low-priority pushes, so the app also fetches on return). A piece added on the iPhone showed on the Mac within seconds, and deletes and archives showed live both ways. |
| 3 | **Account changes while the app is open:** on the owner's iPhone, in a Debug build with `PIANISM_SYNC=1` and History open (simulators hit Apple's "Failed user key sync" bug), (a) turn iCloud off for Pianism in Settings: the not-syncing notice shows, with no relaunch; (b) turn it back on: the notice goes; (c) sign out of iCloud: the notice shows, and note what history is left; (d) sign in again: note what comes back. If (a) shows no notice, iCloud reports the account as available with Pianism's switch off, and that needs a follow-up issue | 2026-10-21, owner's iPhone: (a) passed, and iOS removed the synced history from the device; it offered no "keep on iPhone". Turning the switch off ends the app, and opening it from the app switcher drops launch variables, so relaunch with `devicectl`. (b) passed: the notice went and the history came back at once. (c) and (d) not run; carried to M2's device checks. |
| 4 | **Debug keeps its own history:** on the Mac, delete Pianism, then run it from Xcode in Debug ("Designed for iPad") and add a session with the note `debug #118`, finished rather than running (the running session is shared with Release through the App Group); then install and open a Release build: History, which shows the real history from iCloud, has no session with that note. End-to-end tests run only Debug builds, so no test can open both | Not run yet (#118). |

**Why these are manual:** they need an iCloud account, and CI never uses the owner's (E4). Test
simulators must stay signed out of iCloud: the end-to-end test `testHistorySaysWhenICloudIsntSyncing`
fails on one that's signed in. The two that check sync, `Sync S1` and `Sync S2`, are never picked by
`scripts/simulator-destination.sh`.
