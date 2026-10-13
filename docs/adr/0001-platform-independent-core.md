# 1. A platform-independent core, tested on Linux

- Status: accepted
- Date: 2026-10-13

## Context and problem statement

The rules that matter most (session timing, MIDI auto-detection, stats) must be correct and fully
testable without a simulator or device. Engineering principle E1 says business logic never imports
SwiftUI, SwiftData, CoreMIDI or StoreKit. How do we keep that true as agents add code?

## Decision

`PianismCore` depends only on the Swift standard library, Foundation and Synchronization. It talks
to the outside world through protocols ("ports") that adapter packages implement, and it takes time
from an injected `WallClock` (principle E3).

CI builds and tests `PianismCore` on Linux in the official Swift container. An Apple-only import
fails that job, so the architecture rule is enforced by a machine, not by review alone.

Test doubles shared across packages (for example `ManualClock`) live in a separate
`PianismCoreTestSupport` library, so they never ship in the app.

## Consequences

- Good: the core test suite runs in seconds with `make test-core`, no simulator needed.
- Good: Linux CI minutes are a tenth the cost of macOS minutes, so most testing is cheap.
- Good: the MIDI detector could later ship as an open-source Swift package unchanged.
- Bad: Foundation on Linux differs slightly from Apple's (some formatters, locale data), so
  user-facing formatting stays in the Features layer.
