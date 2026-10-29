import Foundation
import PianismCore
import PianismFeatures
import PianismMIDI
import PianismPersistence
import PianismSystem
import SwiftUI

#if DEBUG
    import notify
#endif

/// The composition root: the only place that wires concrete adapters into the core.
@main
struct PianismApp: App {
    /// Shared with the widget and Live Activity. Must match `Config/Pianism.entitlements`.
    static let appGroup = "group.com.edkarabinus.Pianism"
    /// Holds synced history (SYN-1). Must match `Config/Pianism.entitlements`.
    static let iCloudContainer = "iCloud.com.edkarabinus.Pianism"

    @State private var practice: PracticeModel
    @State private var tags: TagPickerModel
    @State private var history: HistoryModel
    private let historyStore: HistoryStore
    private let midi: CoreMIDINotes?

    init() {
        guard let store = FileRunningSessionStore(appGroup: Self.appGroup) else {
            // Without the App Group, the widget and Live Activity couldn't see the session.
            fatalError("Missing the \(Self.appGroup) App Group entitlement.")
        }
        var clock: any WallClock = SystemClock()
        // After this much practice Practice asks "Still practicing?" (SES-3), and after this much a running session
        // ends itself, in case it was left running (SES-4).
        var nudge: TimeInterval = 90 * 60
        var cap: TimeInterval = 4 * 60 * 60
        // A MIDI session pauses after a minute of silence, ends after 10, and is dropped under a minute played
        // (MIDI-1).
        var midiSettings = MIDISettings()
        // Debug keeps its own history and outbox, so a Release build on the same device never uploads a
        // Debug run's sessions to Production (ADR 0008).
        #if DEBUG
            let dataDirectory = URL.applicationSupportDirectory.appending(path: "Debug")
        #else
            let dataDirectory = URL.applicationSupportDirectory
        #endif
        var historyURL = dataDirectory.appending(path: "History/History.store")
        // Finished sessions wait here while history can't save them (ADR 0007). Only the app moves
        // sessions into history, so this stays out of the App Group.
        let outboxURL = dataDirectory.appending(path: "Outbox")
        // Release syncs with iCloud's Production environment, where schema v1 is deployed (SYN-1, ADR 0008).
        var cloudKitContainer: String? = Self.iCloudContainer
        #if DEBUG
            // End-to-end tests fix the time with PIANISM_NOW (seconds since 1970), shorten the nudge and the cap
            // with PIANISM_NUDGE_SECONDS and PIANISM_CAP_SECONDS, start with no running session, history, outbox
            // or settings with PIANISM_RESET=1, make the history fail to open with PIANISM_BREAK_HISTORY=1,
            // add sessions this version can't show with PIANISM_UNSHOWABLE_SESSIONS (a count), and sync with
            // iCloud's Development environment with PIANISM_SYNC=1. The owner creates the CloudKit schema there
            // with PIANISM_INIT_CLOUDKIT_SCHEMA=1 (ADR 0008). Release builds ignore all nine, the last one
            // below.
            let environment = ProcessInfo.processInfo.environment
            if let seconds = environment["PIANISM_NOW"].flatMap(TimeInterval.init) {
                clock = FixedClock(now: Date(timeIntervalSince1970: seconds))
            }
            if let seconds = environment["PIANISM_NUDGE_SECONDS"].flatMap(TimeInterval.init) {
                nudge = seconds
            }
            if let seconds = environment["PIANISM_CAP_SECONDS"].flatMap(TimeInterval.init) {
                cap = seconds
            }
            // They shorten a MIDI session's timeouts too, with PIANISM_MIDI_PAUSE_SECONDS, PIANISM_MIDI_SAVE_SECONDS
            // and PIANISM_MIDI_MINIMUM_SECONDS, which Release builds ignore as well.
            if let seconds = environment["PIANISM_MIDI_PAUSE_SECONDS"].flatMap(TimeInterval.init) {
                midiSettings.pauseAfter = seconds
            }
            if let seconds = environment["PIANISM_MIDI_SAVE_SECONDS"].flatMap(TimeInterval.init) {
                midiSettings.saveAfter = seconds
            }
            if let seconds = environment["PIANISM_MIDI_MINIMUM_SECONDS"].flatMap(TimeInterval.init) {
                midiSettings.minimumPlayed = seconds
            }
            if environment["PIANISM_RESET"] == "1" {
                try? store.update { $0 = nil }
                try? FileManager.default.removeItem(at: dataDirectory)
                UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "")
            }
            if environment["PIANISM_BREAK_HISTORY"] == "1" {
                historyURL = URL(filePath: "/dev/null/History.store")
            }
            // Debug builds sync only when asked, so tests never touch iCloud.
            if environment["PIANISM_SYNC"] != "1" {
                cloudKitContainer = nil
            }
            if environment["PIANISM_INIT_CLOUDKIT_SCHEMA"] == "1" {
                do {
                    try HistoryStore.initializeCloudKitSchema(cloudKitContainer: Self.iCloudContainer)
                } catch {
                    fatalError("Couldn't create the CloudKit schema: \(error)")
                }
            }
            // End-to-end tests kill the app with this notification (UITestCase.kill). _exit ends it at once with no
            // warning, as SES-6 needs. On a background queue, so a busy main thread can't delay it, and @Sendable, as
            // Swift 6 infers a closure made in this main-actor init as main-actor, and traps when it runs there.
            var token: Int32 = 0
            notify_register_dispatch("com.edkarabinus.Pianism.kill", &token, .global()) { @Sendable _ in _exit(0) }
        #endif
        // One store for both, so sessions and the tags they name are kept, and later synced, together.
        let historyStore = HistoryStore(url: historyURL, cloudKitContainer: cloudKitContainer)
        historyStore.open()
        self.historyStore = historyStore
        #if DEBUG
            if let count = environment["PIANISM_UNSHOWABLE_SESSIONS"].flatMap(Int.init) {
                try? historyStore.addUnshowableSessions(count)
            }
            // End-to-end tests have another device's changes arrive while the app is open with
            // PIANISM_SYNC_ARRIVES_SECONDS: after that long a piece, and after as long again a 30-minute session
            // tagged with it, each saved through a second store on the same file, as an iCloud import saves them.
            // It runs on the main actor, like the rest of launch.
            if let seconds = environment["PIANISM_SYNC_ARRIVES_SECONDS"].flatMap(Double.init) {
                Task { [clock, historyURL] in
                    let elsewhere = HistoryStore(url: historyURL)
                    try? await Task.sleep(for: .seconds(seconds))
                    let piece = try? SwiftDataTagLibrary(store: elsewhere, clock: clock)
                        .add(name: "Synced piece", kind: .piece)
                    try? await Task.sleep(for: .seconds(seconds))
                    var session = PracticeSession(startedAt: clock.now - 30 * 60)
                    try? session.setTags(piece.map { [$0.id] } ?? [])
                    try? session.stop(at: clock.now)
                    try? SwiftDataSessionHistory(store: elsewhere, clock: clock).save(session)
                }
            }
        #endif
        let sessions = SwiftDataSessionHistory(store: historyStore, clock: clock)
        let library = SwiftDataTagLibrary(store: historyStore, clock: clock)
        let outbox = FileSessionOutbox(directory: outboxURL)
        // The notification's answers reach the model once it exists; an answer can launch the app, so the
        // notification is set up here, before launch ends (SES-3).
        let answering = Answering()
        let notifications = UserNotificationNudges(
            answered: { answering.practice?.answerStillPracticing(for: $0) },
            opened: { answering.practice?.open(fromNudgeAbout: $0, pickingEnd: $1) })
        #if DEBUG
            // End-to-end tests have the banner offer the notification whatever the system says with
            // PIANISM_OFFER_NUDGES=1, as the system asks once per install. Release builds ignore it.
            let nudges: any PracticeNudges =
                ProcessInfo.processInfo.environment["PIANISM_OFFER_NUDGES"] == "1" ? OfferingNudges() : notifications
        #else
            let nudges = notifications
        #endif
        let practice = PracticeModel(
            store: store, history: sessions, outbox: outbox, clock: clock, nudges: nudges, defaults: .standard,
            nudge: nudge, cap: cap, midi: midiSettings)
        answering.practice = practice
        self.practice = practice
        #if DEBUG
            // End-to-end tests play notes with PIANISM_MIDI_NOTES, as seconds after launch separated by commas, as the
            // simulator has no piano. Each is dated the clock's launch time plus its offset, so on a fixed clock
            // "0,0,0" is a chord at that time, and on the real clock a slow simulator doesn't move the dates.
            // Release builds ignore it.
            if let notes = environment["PIANISM_MIDI_NOTES"] {
                let launch = (date: clock.now, instant: ContinuousClock.now)
                let offsets = notes.split(separator: ",").compactMap { TimeInterval($0) }
                Task {
                    for offset in offsets {
                        try? await Task.sleep(until: launch.instant + .seconds(offset))
                        practice.noteOn(at: launch.date + offset)
                    }
                }
            }
            // They show a piano as connected with PIANISM_MIDI_PIANO, its name, which Release builds ignore too.
            if let piano = environment["PIANISM_MIDI_PIANO"] {
                practice.connectedPianos = [piano]
            }
        #endif
        // Hears every piano connected over USB or Bluetooth (MIDI-1); the simulator has none. A scripted end-to-end
        // test hears only its script.
        #if DEBUG
            midi = environment["PIANISM_MIDI_NOTES"] == nil ? CoreMIDINotes(clock: clock) : nil
        #else
            midi = CoreMIDINotes(clock: clock)
        #endif
        tags = TagPickerModel(practice: practice, library: library)
        let history = HistoryModel(history: sessions, tags: library, outbox: outbox, running: store, clock: clock)
        #if DEBUG
            // End-to-end tests lengthen Undo with PIANISM_UNDO_SECONDS. Release builds ignore it.
            if let seconds = ProcessInfo.processInfo.environment["PIANISM_UNDO_SECONDS"].flatMap(Int.init) {
                history.undoDuration = .seconds(seconds)
            }
        #endif
        self.history = history
    }

    var body: some Scene {
        WindowGroup {
            RootView(practice: practice, tags: tags, history: history)
                // Shows what iCloud brings from the user's other devices while the app is open (SYN-1). Practice
                // shows nothing synced but tag names, which the picker refreshes.
                .task {
                    for await _ in historyStore.changes {
                        history.refresh()
                        tags.refresh()
                    }
                }
                // Checked at launch rather than when History opens, so its rows don't move under the user (SYN-1).
                .task {
                    for await notSyncing in historyStore.notSyncing {
                        history.isNotSyncing = notSyncing
                    }
                }
                .task {
                    guard let midi else { return }
                    for await date in midi.notes {
                        practice.noteOn(at: date)
                    }
                }
                .task {
                    guard let midi else { return }
                    for await pianos in midi.pianos {
                        practice.connectedPianos = pianos
                    }
                }
        }
    }
}

/// The model the notification's answers reach, which is made after the notification.
@MainActor
private final class Answering {
    weak var practice: PracticeModel?
}

/// Offers the notification and sends none, for end-to-end tests of the banner it's offered in.
private struct OfferingNudges: PracticeNudges {
    func canAskPermission() async -> Bool { true }
    func requestPermission() async {}
    func schedule(after _: TimeInterval, sessionID _: UUID) {}
    func cancel() {}
}

/// A clock that always reads the same time, for end-to-end tests.
private struct FixedClock: WallClock {
    let now: Date
}
