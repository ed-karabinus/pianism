import PianismCore
import SwiftUI

/// Tags the running session with pieces and skills, and adds, renames and archives them (TAG-1, TAG-2).
struct TagPickerView: View {
    @Bindable var model: TagPickerModel

    @Environment(\.dismiss) private var dismiss
    @State private var renaming: Tag?
    @State private var isRenaming = false
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            List {
                section(.piece, title: Text("Pieces", bundle: .module))
                section(.skill, title: Text("Skills", bundle: .module))
            }
            .searchable(text: $model.query, prompt: Text("Find or add a piece or skill", bundle: .module))
            .navigationTitle(Text("Tags", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Done", bundle: .module)
                    }
                    .accessibilityIdentifier(AccessibilityID.tagsDone)
                }
            }
        }
        .onAppear { model.refresh() }
        .alert(Text("Rename", bundle: .module), isPresented: $isRenaming, presenting: renaming) { tag in
            TextField(text: $newName) {
                Text("Name", bundle: .module)
            }
            Button {
                model.rename(tag, to: newName)
            } label: {
                Text("Save", bundle: .module)
            }
            .disabled(!model.canRename(tag, to: newName))
            Button(role: .cancel) {
            } label: {
                Text("Cancel", bundle: .module)
            }
        }
        .alert(Text("Couldn't change your tags", bundle: .module), isPresented: $model.isShowingError) {
            Button(role: .cancel) {
            } label: {
                Text("OK", bundle: .module)
            }
        } message: {
            Text("Pianism couldn't reach its storage. Try again in a moment.", bundle: .module)
        }
    }

    /// The tags of `kind`, led by a button that adds the query as a new one when no tag has its name.
    private func section(_ kind: Tag.Kind, title: Text) -> some View {
        Section {
            if let name = model.newName(kind) {
                Button {
                    model.add(kind)
                } label: {
                    Label {
                        kind == .piece
                            ? Text("Add piece “\(name)”", bundle: .module)
                            : Text("Add skill “\(name)”", bundle: .module)
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
                .accessibilityIdentifier(kind == .piece ? AccessibilityID.tagsAddPiece : AccessibilityID.tagsAddSkill)
            }
            ForEach(model.shown(kind)) { tag in
                row(tag)
            }
        } header: {
            title
        }
    }

    private func row(_ tag: Tag) -> some View {
        let isSelected = model.selected.contains { $0.id == tag.id }
        return Button {
            model.toggle(tag)
        } label: {
            HStack {
                Text(tag.name)
                    .foregroundStyle(.primary)
                if tag.isArchived {
                    Text("Archived", bundle: .module)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    // VoiceOver hears the Selected trait instead.
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .swipeActions(allowsFullSwipe: false) {
            if !tag.isReadOnly {
                Button {
                    model.archive(tag)
                } label: {
                    Label {
                        Text("Archive", bundle: .module)
                    } icon: {
                        Image(systemName: "archivebox")
                    }
                }
                Button {
                    renaming = tag
                    newName = tag.name
                    isRenaming = true
                } label: {
                    Label {
                        Text("Rename", bundle: .module)
                    } icon: {
                        Image(systemName: "pencil")
                    }
                }
                .tint(.indigo)
            }
        }
    }
}

extension Text {
    /// Tags' names as a list, such as "Ballade No. 1, Scales", or "Untagged" if there are none (TAG-2).
    init(tags: [Tag]) {
        if tags.isEmpty {
            self.init("Untagged", bundle: .module)
        } else {
            self.init(tags.map(\.name).formatted(.list(type: .and, width: .narrow)))
        }
    }
}

#Preview("Tagged") {
    TagPickerView(model: .preview())
}

#Preview("Adding, dark, AX5") {
    TagPickerView(model: .preview(query: "Nocturne"))
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
