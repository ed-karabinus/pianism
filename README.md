# Pianism

**A piano practice log that fills itself in.** Connect a digital piano and practice sessions start
and stop as you play. Built for distractible brains: one tap, no guilt, time always visible.

Status: **M1, the core loop**, in progress. You can time a session (pause and resume, and it survives
the app being killed), tag it with pieces and skills, see History by day, add a session you forgot to
time, and fix a finished session's times, tags and note. MIDI auto-start comes in M2. Not on the App
Store yet.

| Practice | Tags | History | Edit session |
| --- | --- | --- | --- |
| <img src="https://github.com/ed-karabinus/pianism/blob/evidence/pr-68/iphone-practicing-tagged.png?raw=true" width="180" alt="Practice, a session running with tags"> | <img src="https://github.com/ed-karabinus/pianism/blob/evidence/pr-68/iphone-tag-picker.png?raw=true" width="180" alt="The tag picker"> | <img src="https://github.com/ed-karabinus/pianism/blob/evidence/pr-77/iphone-history-added.png?raw=true" width="180" alt="History, with a session added after the fact"> | <img src="https://github.com/ed-karabinus/pianism/blob/evidence/pr-76/iphone-edit-session.png?raw=true" width="180" alt="Editing a finished session"> |

The screenshots come from the end-to-end tests, on the iPhone 17 simulator.

## Architecture

```mermaid
flowchart TB
    app["App target<br/>composition root"] --> features
    widget["Widget extension<br/>(M3)"] --> features
    features["PianismFeatures<br/>SwiftUI screens + view models"] --> core
    persistence["PianismPersistence<br/>running-session file, SwiftData + CloudKit"] --> core
    midi["MIDI<br/>CoreMIDI adapter"] --> core
    purchases["Purchases<br/>StoreKit 2"] --> core
    core["PianismCore<br/>pure Swift rules + ports"]
```

Arrows point at dependencies. The core imports nothing Apple-specific and is tested on Linux in CI,
which keeps that boundary honest. See [docs/adr](docs/adr) for the reasoning behind each decision.

## Getting started

Requirements: Xcode 26 or later (developed on Xcode 27), iOS 26+ iPhone and iPad simulators.

```sh
make test-core   # core unit tests, a few seconds
make test-adapters   # adapter integration tests on macOS, against real files
make test-app    # build the app and run end-to-end tests on iPhone and iPad simulators
make test-app DEVICES=iPhone   # just one, when iterating
make lint        # formatting check
make unused      # fail on unused code in the app and the package code it builds (Periphery, pinned)
make mutate      # mutation testing of the core and adapters; minutes, run before milestone checks
```

Open `Pianism.xcodeproj` in Xcode to run the app. To run on a device, create
`Config/Local.xcconfig` containing `DEVELOPMENT_TEAM = <your team ID>` (it is git-ignored).

## Testing

| Layer | Runs |
| --- | --- |
| Unit (Swift Testing, core logic, injected clock) | Every PR, on Linux |
| Integration (adapters against real files on macOS; later SwiftData, StoreKit) | Every PR |
| End-to-end (XCUITest in the simulator) | Every PR |
| Exploratory QA by an agent driving the simulator | Each milestone |
| Device checks with a real piano ([checklist](docs/device-checklist.md)) | Each milestone, by the owner |
