import PianismCore
import SwiftUI

/// Tags a session with pieces and skills, and adds, renames and archives them, and gives pieces details
/// (TAG-1, TAG-2, TAG-3).
struct TagPickerView: View {
    @Bindable var model: TagPickerModel

    @Environment(\.dismiss) private var dismiss
    @State private var renaming: Tag?
    @State private var isRenaming = false
    @State private var newName = ""
    @State private var detailing: Tag?
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            List {
                section(.piece, title: Text("Pieces", bundle: .module))
                section(.skill, title: Text("Skills", bundle: .module))
            }
            .searchable(
                text: $model.query, isPresented: $isSearching, placement: .tagSearch,
                prompt: Text("Find or add a piece or skill", bundle: .module)
            )
            // Searching is how tags are added, so Done stays in reach while typing.
            .searchPresentationToolbarBehavior(.avoidHidingContent)
            .navigationTitle(Text("Tags", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { dismiss() }
                        .accessibilityIdentifier(AccessibilityID.tagsDone)
                }
            }
        }
        .onAppear {
            // The model outlives the sheet, so a search left typed would greet the next opening.
            model.query = ""
            model.refresh()
        }
        .alert(Text("Rename", bundle: .module), isPresented: $isRenaming, presenting: renaming) { tag in
            TextField(text: $newName) {
                Text("Name", bundle: .module)
            }
            Button(LocalizedStringResource("Save", bundle: .module)) { model.rename(tag, to: newName) }
                .disabled(!model.canRename(tag, to: newName))
            Button(role: .cancel) {}
        }
        .sheet(item: $detailing) { tag in
            PieceDetailsView(tag: tag, model: model)
        }
        .storageAlert(Text("Couldn't change your tags", bundle: .module), isPresented: $model.isShowingError)
    }

    /// The tags of `kind`, then a button that adds the query as a new one when no tag has its name. It comes
    /// last, so a tag the search finds, archived or not, is offered before a near-duplicate (TAG-1).
    private func section(_ kind: Tag.Kind, title: Text) -> some View {
        Section {
            ForEach(model.shown(kind)) { tag in
                row(tag)
            }
            if let name = model.newName(kind) {
                Button(
                    kind == .piece
                        ? LocalizedStringResource("Add piece “\(name)”", bundle: .module)
                        : LocalizedStringResource("Add skill “\(name)”", bundle: .module),
                    systemImage: "plus"
                ) {
                    model.add(kind)
                    // Ends the search, so every tag is in reach to add next. Only putting the keyboard away
                    // leaves the search active, and on iPad the next tap on a tag then just ends it.
                    isSearching = false
                }
                .accessibilityIdentifier(kind == .piece ? AccessibilityID.tagsAddPiece : AccessibilityID.tagsAddSkill)
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
                // `Color.primary` and `Color.secondary`, as `.primary` and `.secondary` in a button are its tint.
                VStack(alignment: .leading) {
                    HStack {
                        Text(tag.name)
                            .foregroundStyle(Color.primary)
                        if tag.isArchived {
                            Text("Archived", bundle: .module)
                                .foregroundStyle(Color.secondary)
                        }
                    }
                    if let details = tag.details {
                        Text(details)
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                    }
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
                Button(LocalizedStringResource("Archive", bundle: .module), systemImage: "archivebox") {
                    model.archive(tag)
                }
                Button(LocalizedStringResource("Rename", bundle: .module), systemImage: "pencil") {
                    renaming = tag
                    newName = tag.name
                    isRenaming = true
                }
                .tint(.indigo)
            }
            if model.canHaveDetails(tag) {
                Button(LocalizedStringResource("Details", bundle: .module), systemImage: "info.circle") {
                    detailing = tag
                }
                .tint(.teal)
                .accessibilityIdentifier(AccessibilityID.tagsDetails)
            }
        }
    }
}

extension SearchFieldPlacement {
    /// Under the title, always shown. Searching is how tags are added, and on an iOS 26 iPad the
    /// default placement hides the field until the list is pulled down.
    fileprivate static var tagSearch: SearchFieldPlacement {
        #if os(iOS)
            .navigationBarDrawer(displayMode: .always)
        #else
            .automatic
        #endif
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

// Tagged, so the largest text shows a piece's details under its name.
#Preview("Tagged, dark, AX5") {
    TagPickerView(model: .preview())
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}

#Preview("Adding") {
    TagPickerView(model: .preview(query: "Nocturne"))
}
