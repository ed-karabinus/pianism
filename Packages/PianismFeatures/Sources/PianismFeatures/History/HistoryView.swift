import PianismCore
import SwiftUI

/// The History screen: finished sessions grouped by day, newest first, with each day's total (HIS-1).
struct HistoryView: View {
    @Bindable var model: HistoryModel
    /// The session a swipe asked to delete, until the deletion is confirmed or cancelled (SES-5).
    @State private var confirmingDeletion: PracticeSession?
    /// Moves VoiceOver to Undo when it appears, since it lasts only 5 seconds.
    @AccessibilityFocusState private var isUndoFocused: Bool

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("History", bundle: .module))
                .toolbar {
                    Button(LocalizedStringResource("Add session", bundle: .module), systemImage: "plus") { model.add() }
                        .accessibilityIdentifier(AccessibilityID.historyAdd)
                }
                .safeAreaInset(edge: .bottom) {
                    if model.pendingDeletion != nil { undoBar }
                }
        }
        .onAppear { model.refresh() }
        // Leaving History ends a deletion's undo, as leaving the app does (Ed's call, 2026-10-18).
        .onDisappear { model.commitDelete() }
        .sheet(item: $model.editing, onDismiss: model.refresh) { edit in
            SessionEditorView(editor: edit.editor, tags: edit.tags) { model.delete(edit.editor.session) }
        }
        .confirmationDialog(
            Text("Delete this session?", bundle: .module),
            isPresented: Binding {
                confirmingDeletion != nil
            } set: {
                if !$0 { confirmingDeletion = nil }
            },
            titleVisibility: .visible, presenting: confirmingDeletion
        ) { session in
            Button(LocalizedStringResource("Delete session", bundle: .module), role: .destructive) {
                model.delete(session)
            }
            .accessibilityIdentifier(AccessibilityID.deleteConfirm)
        }
        // Undo lasts 5 seconds (`undoDuration`). A new deletion or Undo cancels the wait, but only at the next update, so
        // the ID is checked again: a late wait mustn't commit the next deletion.
        .task(id: model.pendingDeletion?.id) {
            guard let id = model.pendingDeletion?.id, (try? await Task.sleep(for: model.undoDuration)) != nil,
                model.pendingDeletion?.id == id
            else { return }
            model.commitDelete()
        }
        .storageAlert(Text("Couldn't delete that session", bundle: .module), isPresented: $model.isShowingDeleteError)
    }

    /// Says a session was deleted, with Undo while it can be (SES-5).
    private var undoBar: some View {
        HStack {
            Text("Session deleted", bundle: .module)
            Spacer()
            Button(LocalizedStringResource("Undo", bundle: .module)) { model.undoDelete() }
                .bold()
                .accessibilityFocused($isUndoFocused)
                .accessibilityIdentifier(AccessibilityID.historyUndo)
        }
        .padding()
        .background(.regularMaterial, in: .capsule)
        .padding()
        .onAppear { isUndoFocused = true }
    }

    @ViewBuilder private var content: some View {
        if model.days.isEmpty, model.loadFailed {
            ContentUnavailableView(
                LocalizedStringResource("Couldn't load your history", bundle: .module),
                systemImage: "exclamationmark.triangle",
                description: Text("Restart Pianism to try again.", bundle: .module)
            )
            .accessibilityIdentifier(AccessibilityID.historyUnavailable)
        } else if model.days.isEmpty {
            ContentUnavailableView(
                LocalizedStringResource("No practice yet", bundle: .module), systemImage: "music.note.list",
                description: Text("Sessions you finish appear here.", bundle: .module)
            )
            .accessibilityIdentifier(AccessibilityID.historyEmpty)
        } else {
            List {
                if model.loadFailed {
                    Label(
                        LocalizedStringResource(
                            "Couldn't load your earlier history. Sessions waiting to be saved are shown.",
                            bundle: .module),
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(AccessibilityID.historyUnavailable)
                }
                ForEach(model.days) { day in
                    Section {
                        ForEach(day.sessions) { session in
                            let isWaiting = model.waitingIDs.contains(session.id)
                            let title =
                                isWaiting
                                ? Text("\(session.times), not saved yet", bundle: .module) : Text(session.times)
                            // A finished session's practice time is fixed, so the date passed here is ignored.
                            let row = TimedRow(
                                title: title, detail: Text(tags: model.tagIndex.tags(for: session.tagIDs)),
                                duration: session.elapsed(at: .distantPast))
                            // A session waiting to be saved can't be edited yet (ADR 0007).
                            Group {
                                if isWaiting {
                                    row
                                } else {
                                    Button {
                                        model.edit(session)
                                    } label: {
                                        row
                                    }
                                    .tint(.primary)
                                }
                            }
                            .accessibilityIdentifier(AccessibilityID.historySession)
                            .swipeActions {
                                if model.canDelete(session) {
                                    // Not the destructive role, which would remove the row before it's confirmed.
                                    Button(LocalizedStringResource("Delete", bundle: .module), systemImage: "trash") {
                                        confirmingDeletion = session
                                    }
                                    .tint(.red)
                                    .accessibilityIdentifier(AccessibilityID.historyDelete)
                                }
                            }
                        }
                    } header: {
                        TimedRow(title: title(for: day), duration: day.total)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier(AccessibilityID.historyDay)
                    }
                }
            }
        }
    }

    /// "Today", "Yesterday", or the date, such as "Wednesday, October 14".
    private func title(for day: PracticeDay) -> Text {
        if model.calendar.isDate(day.start, inSameDayAs: model.now) {
            return Text("Today", bundle: .module)
        }
        if let yesterday = model.calendar.date(byAdding: .day, value: -1, to: model.now),
            model.calendar.isDate(day.start, inSameDayAs: yesterday)
        {
            return Text("Yesterday", bundle: .module)
        }
        return Text(day.start.formatted(.dateTime.weekday(.wide).month(.wide).day()))
    }
}

extension PracticeSession {
    /// When the session ran, such as "3:30 – 4:00 PM", as History lists it.
    var times: String { (startedAt..<(endedAt ?? startedAt)).formatted(.interval.hour().minute()) }
}

/// A title, and any detail under it, with a practice time after them, read by VoiceOver as one element:
/// a day's header or a session.
struct TimedRow: View {
    let title: Text
    var detail: Text?
    let duration: TimeInterval

    var body: some View {
        LabeledContent {
            Text(ElapsedTime.display(duration)).monospacedDigit()
        } label: {
            title
            detail
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(detail.map { Text("\(title), \($0)", bundle: .module) } ?? title)
        .accessibilityValue(ElapsedTime.spoken(duration))
    }
}

#Preview("Some practice, dark, AX5") {
    HistoryView(model: .preview())
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}

#Preview("Undo after deleting") {
    HistoryView(model: .preview(deleting: true))
}

#Preview("Undo after deleting, dark, AX5") {
    HistoryView(model: .preview(deleting: true))
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}

#Preview("Empty") {
    HistoryView(model: .preview(empty: true))
}

#Preview("History couldn't load, sessions waiting") {
    HistoryView(model: .preview(waiting: true))
}
