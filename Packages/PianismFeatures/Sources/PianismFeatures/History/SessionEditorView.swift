import PianismCore
import SwiftUI

/// Edits a finished session (SES-5). Changes reach history only when saved.
struct SessionEditorView: View {
    @Bindable var editor: SessionEditorModel
    let tags: TagPickerModel

    @Environment(\.dismiss) private var dismiss
    @State private var isPickingTags = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(selection: $editor.start, in: ...editor.end) {
                        Text("Start", bundle: .module)
                    }
                    .disabled(editor.isReadOnly)
                    DatePicker(selection: $editor.end, in: editor.start...editor.latestEnd) {
                        Text("End", bundle: .module)
                    }
                    .disabled(editor.isReadOnly)
                    .accessibilityIdentifier(AccessibilityID.editorEnd)
                    // A finished session's practice time is fixed, so the date passed here is ignored.
                    TimedRow(
                        title: Text("Practice time", bundle: .module),
                        duration: editor.session.elapsed(at: .distantPast))
                } footer: {
                    if editor.isReadOnly {
                        Text(
                            "A newer version of Pianism changed this session. Update Pianism to change it.",
                            bundle: .module)
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
            }
            .navigationTitle(Text("Edit Session", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        if editor.save() { dismiss() }
                    }
                    .disabled(editor.isReadOnly)
                    .accessibilityIdentifier(AccessibilityID.editorSave)
                }
            }
            .sheet(isPresented: $isPickingTags) {
                TagPickerView(model: tags)
            }
        }
        .storageAlert(Text("Couldn't save that change", bundle: .module), isPresented: $editor.isShowingError)
    }
}

#Preview("Tagged") {
    let edit = SessionEdit.preview()
    SessionEditorView(editor: edit.editor, tags: edit.tags)
}

#Preview("Written by a newer version, dark, AX5") {
    let edit = SessionEdit.preview(readOnly: true)
    SessionEditorView(editor: edit.editor, tags: edit.tags)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
