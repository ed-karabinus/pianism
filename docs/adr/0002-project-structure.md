# 2. Thin Xcode project plus local Swift packages

- Status: accepted
- Date: 2026-10-13

## Context and problem statement

Pianism is an iOS app with an app target, UI tests, and (from M3) a widget extension. Most code is
written by AI agents working in parallel git worktrees. How should the project be structured so that
module boundaries are enforced, merge conflicts are rare, and nothing depends on hand-editing
`project.pbxproj`?

## Considered options

1. A single Xcode project with all code in app targets.
2. A project generator (XcodeGen or Tuist) with the `.xcodeproj` git-ignored.
3. A thin, checked-in Xcode project using folder-synchronized groups, with all logic in local Swift
   packages.

## Decision

Option 3.

- `Pianism.xcodeproj` holds only the app and test targets. Their folders (`App/`, `AppUITests/`) are
  *synchronized groups*: Xcode picks up any file added to them, so adding a file never touches
  `project.pbxproj`.
- Code lives in local packages under `Packages/`: `PianismCore` (pure Swift rules),
  `PianismFeatures` (SwiftUI), and one package per adapter as they arrive (Persistence, MIDI,
  Purchases, System).
- Build settings live in `Config/*.xcconfig`, not in the project file, so every change is a readable
  diff.

## Consequences

- Good: package boundaries are compiler-enforced; `PianismCore` cannot import UI code by accident.
- Good: no extra tool to install, pin or update; the project opens in a stock Xcode.
- Good: agents rarely conflict on the project file, because it almost never changes.
- Bad: adding a *target* (the widget extension in M3) still means editing `project.pbxproj` once,
  carefully, in its own reviewed PR.
- Bad: local packages need their own `Package.swift` upkeep (platforms, dependencies).

## Platform baseline (updated 2026-10-13)

Owner decisions after the plan review: **iOS 26 minimum**, **universal for iPhone and iPad**.
`Config/Shared.xcconfig` sets the deployment target and device family. Every package uses
`swift-tools-version: 6.2`, declares `.iOS(.v26)` plus the macOS version its tests need on the Mac,
and sets `.treatAllWarnings(as: .error)` on every target, so warnings are fatal wherever a package
is built from. This replaced a command-line
override that clashed with Xcode 26's `-suppress-warnings` for dependency packages. End-to-end
tests run on both an iPhone and an iPad simulator.

Amended 2026-10-16: `PianismFeatures` declares macOS 26 so its view models are tested on the Mac in
seconds (`make test-features`). Its views must therefore compile for macOS too; an iOS-only API needs
`#if os(iOS)`. The app still ships on iOS only.
