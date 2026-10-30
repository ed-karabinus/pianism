import SwiftUI

#if os(iOS)
    import UIKit
#endif

/// The app's top-level screen: a tab per area.
public struct RootView: View {
    let practice: PracticeModel
    let tags: TagPickerModel
    let history: HistoryModel

    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = AppTab.practice

    public init(practice: PracticeModel, tags: TagPickerModel, history: HistoryModel) {
        self.practice = practice
        self.tags = tags
        self.history = history
    }

    public var body: some View {
        TabView(selection: $tab) {
            Tab(LocalizedStringResource("Practice", bundle: .module), systemImage: "pianokeys", value: .practice) {
                PracticeView(model: practice, tags: tags) { id in
                    history.edit(id: id)
                    tab = .history
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier(AccessibilityID.root)
            }
            Tab(LocalizedStringResource("History", bundle: .module), systemImage: "calendar", value: .history) {
                HistoryView(model: history)
            }
        }
        // Asks "Still practicing?", ends a timer session at the cap, and pauses or ends a silent MIDI session, while
        // the app is on screen on any tab, as on an iPad on a music stand (SES-3, SES-4, MIDI-1). Only while the app
        // is in front: away, the notification asks, and a refresh at the nudge would cancel it as it arrives. The
        // tolerance keeps each wake within a second: with none, a long sleep may wake late by a share of its length,
        // and a MIDI session saved itself up to half a minute after its 10 minutes.
        .task(id: scenePhase == .active ? practice.session : nil) {
            guard scenePhase == .active else { return }
            while let next = practice.nextRefresh,
                (try? await Task.sleep(
                    for: .seconds(next.timeIntervalSince(practice.clock.now)), tolerance: .seconds(1))) != nil
            {
                practice.tick()
            }
        }
        // Lets the screen lock once Practice has waited 15 minutes for a note with a piano connected (MIDI-R5).
        .task(id: scenePhase == .active ? practice.readyUntil : nil) {
            while scenePhase == .active, let until = practice.readyUntil,
                (try? await Task.sleep(
                    for: .seconds(until.timeIntervalSince(practice.clock.now)), tolerance: .seconds(1))) != nil
            {
                practice.tick()
            }
        }
        #if os(iOS)
            .onChange(of: practice.keepsScreenAwake(showingPractice: tab == .practice), initial: true) { _, awake in
                UIApplication.shared.isIdleTimerDisabled = awake
            }
        #endif
        // The notification opens Practice, to its question or the end being picked (SES-3).
        .onChange(of: practice.nudgeOpened) { _, opened in
            if opened != nil {
                tab = .practice
            }
        }
        // Shows changes made while the app was away, and moves "today" along after midnight. Leaving the screen,
        // inactive included, stores a MIDI session's last note (MIDI-1): swiped away in the app switcher, the app
        // is killed without reaching the background. Reaching the background ends a deletion's undo (SES-5).
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                practice.cameToFront()
                history.refresh()
            } else {
                practice.leaveForeground()
                if scenePhase == .background { history.commitDelete() }
            }
        }
    }
}

/// Accessibility identifiers, which the UI tests look up by the same strings.
enum AccessibilityID {
    static let root = "root"
    static let practiceStatus = "practice.status"
    static let practiceElapsed = "practice.elapsed"
    static let practiceLastSession = "practice.last-session"
    static let practiceTooShort = "practice.too-short"
    static let practiceWaiting = "practice.waiting"
    static let practicePianos = "practice.pianos"
    static let practiceStart = "practice.start"
    static let practicePause = "practice.pause"
    static let practiceResume = "practice.resume"
    static let practiceStop = "practice.stop"
    static let practiceTags = "practice.tags"
    static let practiceStillPracticing = "practice.still-practicing"
    static let practiceStillPracticingYes = "practice.still-practicing-yes"
    static let practiceRemindMe = "practice.remind-me"
    static let practiceStoppedEarlier = "practice.stopped-earlier"
    static let practiceStoppedAt = "practice.stopped-at"
    static let practiceStopAt = "practice.stop-at"
    static let practiceCapped = "practice.capped"
    static let practiceCappedEdit = "practice.capped-edit"
    static let pianosPair = "pianos.pair"
    static let pianosDone = "pianos.done"
    static let pianosReplug = "pianos.replug"
    static let tagsAddPiece = "tags.add-piece"
    static let tagsAddSkill = "tags.add-skill"
    static let tagsDone = "tags.done"
    static let tagsDetails = "tags.details"
    static let detailsComposer = "details.composer"
    static let detailsTempo = "details.tempo"
    static let detailsSave = "details.save"
    static let historyEmpty = "history.empty"
    static let historyUnavailable = "history.unavailable"
    static let historyUnshowable = "history.unshowable"
    static let historyNotSyncing = "history.not-syncing"
    static let historyWeek = "history.week"
    static let historyWeekTag = "history.week-tag"
    static let historyWeekByTag = "history.week-by-tag"
    static let historyDay = "history.day"
    static let historySession = "history.session"
    static let historyAdd = "history.add"
    static let editorTags = "editor.tags"
    static let editorSave = "editor.save"
    static let editorCancel = "editor.cancel"
    static let editorEnd = "editor.end"
    static let editorNote = "editor.note"
    static let editorOverlap = "editor.overlap"
    static let editorOverlapOff = "editor.overlap-off"
    static let editorDelete = "editor.delete"
    static let historyDelete = "history.delete"
    static let historyUndo = "history.undo"
    static let deleteConfirm = "delete.confirm"
}

/// The app's tabs, so the cap banner's Edit can switch to History (SES-4).
private enum AppTab {
    case practice, history
}

#Preview {
    let practice = PracticeModel.preview(.ready)
    RootView(practice: practice, tags: .preview(for: practice), history: .preview())
}
