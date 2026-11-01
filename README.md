# Pianism

**A piano practice log that fills itself in.** Connect a digital piano and practice sessions start
and stop as you play. Built for distractible brains: one tap, no guilt, time always visible.

Status: **M1, the core loop**, done. You can time a session (pause and resume, and it survives the
app being killed), tag it with pieces and skills, give a piece its composer and target tempo, see
History by day, add a session you forgot to time, fix or delete a finished one, and keep it all in
sync across your devices through iCloud. MIDI auto-start comes in M2. Not on the App Store yet.

| Practice | Tags | History | Edit session |
| --- | --- | --- | --- |
| <img src="https://github.com/ed-karabinus/pianism/blob/evidence/pr-68/iphone-practicing-tagged.png?raw=true" width="180" alt="Practice, a session running with tags"> | <img src="https://github.com/ed-karabinus/pianism/blob/evidence/pr-103/iphone-with-details.png?raw=true" width="180" alt="The tag picker, with a piece's composer and tempo"> | <img src="https://github.com/ed-karabinus/pianism/blob/evidence/pr-77/iphone-history-added.png?raw=true" width="180" alt="History, with a session added after the fact"> | <img src="https://github.com/ed-karabinus/pianism/blob/evidence/pr-76/iphone-edit-session.png?raw=true" width="180" alt="Editing a finished session"> |

The screenshots come from the end-to-end tests, on the iPhone 17 simulator.

## Architecture

```mermaid
flowchart TB
    app["App target<br/>composition root"] --> features
    app --> glance
    widget["Widget extension<br/>today's practice"] --> glance
    widget --> persistence
    widget --> core
    glance --> core
    glance["PianismGlance<br/>what the app and the widget both name"]
    features["PianismFeatures<br/>SwiftUI screens + view models"] --> core
    persistence["PianismPersistence<br/>running-session file, SwiftData + CloudKit"] --> core
    midi["PianismMIDI<br/>CoreMIDI, every connected piano"] --> core
    purchases["Purchases<br/>StoreKit 2"] --> core
    core["PianismCore<br/>pure Swift rules + ports"]
```

Arrows point at dependencies. The core imports nothing Apple-specific and is tested on Linux in CI,
which keeps that boundary honest. See [docs/adr](docs/adr) for the reasoning behind each decision.

## Getting started

Requirements: Xcode 26 or later (developed on Xcode 27), iOS 26+ iPhone and iPad simulators.

```sh
make test-core   # core unit tests, a few seconds
make test-features   # view-model unit tests on the Mac, seconds
make test-adapters   # adapter integration tests on macOS, against real files
make test-app    # build the app and run end-to-end tests on iPhone and iPad simulators
make test-app DEVICES=iPhone   # just one, when iterating
make lint        # formatting check
make unused      # fail on unused code in the app and the package code it builds (Periphery, pinned)
make mutate      # mutation testing of the core and adapters; minutes, run before milestone checks
```

Open `Pianism.xcodeproj` in Xcode to run the app. To run on a device, create
`Config/Local.xcconfig` containing `DEVELOPMENT_TEAM = <your team ID>` (it is git-ignored). The iCloud
container and App Group in `Config/Pianism.entitlements` are the owner's; use your own identifiers.

## Testing

| Layer | Runs |
| --- | --- |
| Unit (Swift Testing: core logic, injected clock, on Linux; view models, on macOS) | Every PR |
| Integration (adapters on macOS, against real files and SwiftData; later StoreKit) | Every PR |
| End-to-end (XCUITest in the simulator) | Every PR |
| Exploratory QA by an agent driving the simulator | Each milestone |
| Device checks with a real piano ([checklist](docs/device-checklist.md)) | Each milestone, by the owner |

## License

Copyright © 2026 Edward J. Karabinus. The source is public to read under the
[PolyForm Strict License 1.0.0](LICENSE.md), which allows only noncommercial use: no distributing
it, changing it or building on it. The license's text is what counts.
