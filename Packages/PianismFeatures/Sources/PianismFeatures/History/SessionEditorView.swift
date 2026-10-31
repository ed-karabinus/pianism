import PianismCore
import SwiftUI

/// Edits a finished session, or one being added (SES-5). Changes reach history only when saved, and
/// closing with unsaved changes asks first.
struct SessionEditorView: View {
    @Bindable var editor: SessionEditorModel
    let tags: TagPickerModel
    /// Deletes the session once it's confirmed; History then offers Undo (SES-5).
    var onDelete: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var isPickingTags = false
    @State private var isConfirmingDiscard = false
    @State private var isConfirmingDelete = false
    /// Off once the user asks not to be warned about overlapping sessions again, on this device.
    @AppStorage("showsOverlapWarning") private var showsOverlapWarning = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(selection: $editor.start, in: editor.startRange) {
                        Text("Start", bundle: .module)
                    }
                    .disabled(editor.isReadOnly)
                    DatePicker(selection: $editor.end, in: editor.endRange) {
                        Text("End", bundle: .module)
                    }
                    .disabled(editor.isReadOnly)
                    .accessibilityIdentifier(AccessibilityID.editorEnd)
                    // A finished session's practice time is fixed, so the date passed here is ignored.
                    TimedRow(
                        title: Text("Practice time", bundle: .module),
                        duration: editor.session.elapsed(at: .distantPast))
                } footer: {
                    if editor.isDeleted {
                        Text("This session was deleted on another device.", bundle: .module)
                            .accessibilityIdentifier(AccessibilityID.editorDeleted)
                    } else if editor.isReadOnly {
                        Text(
                            "A newer version of Pianism changed this session. Update Pianism to change it.",
                            bundle: .module)
                    } else if showsOverlapWarning, let overlap = editor.overlap {
                        // A footer shows only its first view, so the button needs a stack to appear.
                        VStack(alignment: .leading) {
                            Text(
                                "This shares \(ElapsedTime.spoken(overlap.shared)) of practice with your \(overlap.session.times) session, so the day's total counts it twice.",
                                bundle: .module
                            )
                            .accessibilityIdentifier(AccessibilityID.editorOverlap)
                            Button(LocalizedStringResource("Don't show again", bundle: .module)) {
                                showsOverlapWarning = false
                            }
                            .accessibilityIdentifier(AccessibilityID.editorOverlapOff)
                        }
                    }
                }
                Button {
                    isPickingTags = true
                } label: {
                    LabeledContent {
                        Text(tags: tags.selected)
                    } label: {
                        Text("Tags", bundle: .module).foregroundStyle(Color.primary)
                    }
                }
                .disabled(editor.isReadOnly)
                .accessibilityIdentifier(AccessibilityID.editorTags)
                TextField(text: $editor.note, axis: .vertical) {
                    Text("Note", bundle: .module)
                }
                .disabled(editor.isReadOnly)
                .accessibilityIdentifier(AccessibilityID.editorNote)
                if !editor.isNew, !editor.isReadOnly, !editor.isDeleted {
                    Section {
                        Button(LocalizedStringResource("Delete session", bundle: .module), role: .destructive) {
                            isConfirmingDelete = true
                        }
                        .accessibilityIdentifier(AccessibilityID.editorDelete)
                        .confirmationDialog(
                            Text("Delete this session?", bundle: .module), isPresented: $isConfirmingDelete,
                            titleVisibility: .visible
                        ) {
                            Button(LocalizedStringResource("Delete session", bundle: .module), role: .destructive) {
                                onDelete()
                            }
                            .accessibilityIdentifier(AccessibilityID.deleteConfirm)
                        }
                    }
                }
            }
            .navigationTitle(
                editor.isNew ? Text("Add session", bundle: .module) : Text("Edit session", bundle: .module)
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        if editor.hasChanges { isConfirmingDiscard = true } else { dismiss() }
                    }
                    .accessibilityIdentifier(AccessibilityID.editorCancel)
                    .confirmationDialog(
                        Text("Discard changes?", bundle: .module), isPresented: $isConfirmingDiscard,
                        titleVisibility: .visible
                    ) {
                        Button(LocalizedStringResource("Discard", bundle: .module), role: .destructive) { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        if editor.save() { dismiss() }
                    }
                    .disabled(editor.isReadOnly || editor.isDeleted)
                    .accessibilityIdentifier(AccessibilityID.editorSave)
                }
            }
            .sheet(isPresented: $isPickingTags) {
                TagPickerView(model: tags)
            }
        }
        .interactiveDismissDisabled(editor.hasChanges)
        .storageAlert(Text("Couldn't save that change", bundle: .module), isPresented: $editor.isShowingError)
        .alert(Text("Couldn't save that change", bundle: .module), isPresented: $editor.isShowingDeleted) {
        } message: {
            Text("This session was deleted on another device.", bundle: .module)
        }
    }
}

#Preview("Tagged") {
    let edit = SessionEdit.preview()
    SessionEditorView(editor: edit.editor, tags: edit.tags)
}

#Preview("Deleted on another device") {
    let edit = SessionEdit.preview(deleted: true)
    SessionEditorView(editor: edit.editor, tags: edit.tags)
}

#Preview("Overlapping another session") {
    let edit = SessionEdit.preview(overlapping: true)
    SessionEditorView(editor: edit.editor, tags: edit.tags)
}

#Preview("Written by a newer version, dark, AX5") {
    let edit = SessionEdit.preview(readOnly: true)
    SessionEditorView(editor: edit.editor, tags: edit.tags)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
