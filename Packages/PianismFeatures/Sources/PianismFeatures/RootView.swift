import SwiftUI

/// The app's top-level screen: a tab per area.
public struct RootView: View {
    let practice: PracticeModel
    let tags: TagPickerModel
    let history: HistoryModel

    @Environment(\.scenePhase) private var scenePhase

    public init(practice: PracticeModel, tags: TagPickerModel, history: HistoryModel) {
        self.practice = practice
        self.tags = tags
        self.history = history
    }

    public var body: some View {
        TabView {
            Tab(LocalizedStringResource("Practice", bundle: .module), systemImage: "pianokeys") {
                PracticeView(model: practice, tags: tags)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier(AccessibilityID.root)
            }
            Tab(LocalizedStringResource("History", bundle: .module), systemImage: "calendar") {
                HistoryView(model: history)
            }
        }
        // Shows changes made while the app was away, and moves "today" along after midnight.
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                practice.refresh()
                history.refresh()
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
    static let tagsAddPiece = "tags.add-piece"
    static let tagsAddSkill = "tags.add-skill"
    static let tagsDone = "tags.done"
    static let historyEmpty = "history.empty"
    static let historyUnavailable = "history.unavailable"
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
}

#Preview {
    let practice = PracticeModel.preview(.ready)
    RootView(practice: practice, tags: .preview(for: practice), history: .preview())
}
