import SwiftUI

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
        // The notification opens Practice, to its question or the end being picked (SES-3).
        .onChange(of: practice.nudgeOpened) { _, opened in
            if opened != nil {
                tab = .practice
            }
        }
        // Shows changes made while the app was away, and moves "today" along after midnight. Leaving the
        // app ends a deletion's undo (SES-5).
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                practice.refresh()
                history.refresh()
            } else if scenePhase == .background {
                history.commitDelete()
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
    static let practiceWaiting = "practice.waiting"
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
    static let tagsAddPiece = "tags.add-piece"
    static let tagsAddSkill = "tags.add-skill"
    static let tagsDone = "tags.done"
    static let historyEmpty = "history.empty"
    static let historyUnavailable = "history.unavailable"
    static let historyUnshowable = "history.unshowable"
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
