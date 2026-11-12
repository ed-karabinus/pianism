import PianismCore
import SwiftUI

/// Tags a session with pieces and skills, and adds, renames, archives and merges them, adds them inside others, moves
/// them, and gives pieces details (TAG-1, TAG-2, TAG-3, TAG-4, TAG-5).
struct TagPickerView: View {
    @Bindable var model: TagPickerModel

    @Environment(\.dismiss) private var dismiss
    @State private var renaming: Tag?
    @State private var isRenaming = false
    @State private var newName = ""
    @State private var detailing: Tag?
    @State private var merging: Tag?
    @State private var moving: Tag?
    @State private var addingInside: Tag?
    @State private var isAddingInside = false
    @State private var archiveBlocked: Tag?
    @State private var isArchiveBlocked = false
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            List {
                section(.piece, title: Text("Pieces", bundle: .module))
                section(.skill, title: Text("Skills", bundle: .module))
                mergedSection
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
        .onAppear { model.open() }
        .alert(Text("Rename", bundle: .module), isPresented: $isRenaming, presenting: renaming) { tag in
            TextField(text: $newName) {
                Text("Name", bundle: .module)
            }
            Button(LocalizedStringResource("Save", bundle: .module)) { model.rename(tag, to: newName) }
                .disabled(!model.canRename(tag, to: newName))
            Button(role: .cancel) {}
        }
        .alert(addInsideTitle, isPresented: $isAddingInside, presenting: addingInside) { parent in
            TextField(text: $newName) {
                Text("Name", bundle: .module)
            }
            .accessibilityIdentifier(AccessibilityID.tagsAddInsideName)
            Button(LocalizedStringResource("Add", bundle: .module)) {
                model.add(newName, inside: parent)
                // Ends the search the model cleared, as adding at the top level does.
                isSearching = false
            }
            .disabled(!model.canAdd(newName, inside: parent))
            Button(role: .cancel) {}
        }
        // D1: what's inside goes first, so an archived tag never has anything live inside it.
        .alert(archiveBlockedTitle, isPresented: $isArchiveBlocked, presenting: archiveBlocked) { _ in }
        .sheet(item: $detailing) { tag in
            PieceDetailsView(tag: tag, model: model)
        }
        .sheet(item: $merging) { tag in
            MergeTagView(tag: tag, model: model)
        }
        .sheet(item: $moving) { tag in
            MoveTagView(tag: tag, model: model)
        }
        .storageAlert(Text("Couldn't change your tags", bundle: .module), isPresented: $model.isShowingError)
    }

    /// The tags of `kind`, then a button that adds the query as a new one when no tag has its name, so a tag
    /// the search finds, archived or not, is offered before a near-duplicate (TAG-1).
    private func section(_ kind: Tag.Kind, title: Text) -> some View {
        Section {
            ForEach(model.shown(kind)) { tag in
                let children = model.shown(inside: tag)
                if children.isEmpty {
                    row(tag)
                } else {
                    // D3: folded unless a child was chosen when the picker opened. The name still tags the parent.
                    let isUnfolded = model[isUnfolded: tag.id]
                    DisclosureGroup(isExpanded: $model[isUnfolded: tag.id]) {
                        ForEach(children) { child in
                            row(child)
                        }
                        if model.canAddInside(tag) {
                            Button(
                                LocalizedStringResource("Add inside \(tag.name)", bundle: .module), systemImage: "plus"
                            ) {
                                startAddingInside(tag)
                            }
                            .accessibilityIdentifier(AccessibilityID.tagsAddInside)
                        }
                    } label: {
                        row(tag)
                            // The name is a button, so VoiceOver hears the fold here, and can change it.
                            .accessibilityValue(
                                isUnfolded ? Text("Expanded", bundle: .module) : Text("Collapsed", bundle: .module)
                            )
                            .accessibilityAction(
                                named: isUnfolded ? Text("Collapse", bundle: .module) : Text("Expand", bundle: .module)
                            ) {
                                model[isUnfolded: tag.id].toggle()
                            }
                    }
                }
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

    /// Tags merged away, each with a way to undo it, at any time (TAG-4).
    @ViewBuilder private var mergedSection: some View {
        let merged = model.merged
        if !merged.isEmpty {
            Section {
                ForEach(merged, id: \.tag.id) { tag, kept in
                    LabeledContent {
                        if !tag.isReadOnly {
                            Button(LocalizedStringResource("Undo", bundle: .module)) { model.undoMerge(tag) }
                                // Otherwise a tap anywhere on the row counts.
                                .buttonStyle(.borderless)
                                .accessibilityLabel(Text("Undo merging \(tag.name)", bundle: .module))
                                .accessibilityIdentifier(AccessibilityID.tagsUndoMerge)
                        }
                    } label: {
                        Text(tag.name)
                        Text("Merged into \(kept.name)", bundle: .module)
                    }
                }
            } header: {
                Text("Merged", bundle: .module)
            }
        }
    }

    /// "New skill inside Scales", for the tag being added inside.
    private var addInsideTitle: Text {
        let name = addingInside?.name ?? ""
        return addingInside?.kind == .piece
            ? Text("New piece inside \(name)", bundle: .module) : Text("New skill inside \(name)", bundle: .module)
    }

    /// "Archive the 3 pieces inside “Études, Op. 10” first.", for the tag that couldn't be archived (D1).
    /// An alert title flattens a `Text` to plain characters, which skips the plural markup, so the plural is
    /// worked out here first.
    private var archiveBlockedTitle: String {
        let count = archiveBlocked.map(model.liveChildren(of:)) ?? 0
        let name = archiveBlocked?.name ?? ""
        let title =
            archiveBlocked?.kind == .piece
            ? AttributedString(
                localized: "Archive the ^[\(count) piece](inflect: true) inside “\(name)” first.", bundle: .module)
            : AttributedString(
                localized: "Archive the ^[\(count) skill](inflect: true) inside “\(name)” first.", bundle: .module)
        return String(title.characters)
    }

    private func startAddingInside(_ parent: Tag) {
        addingInside = parent
        newName = ""
        isAddingInside = true
    }

    private func row(_ tag: Tag) -> some View {
        let isSelected = model.selected.contains { $0.id == tag.id }
        return Button {
            model.toggle(tag)
        } label: {
            HStack {
                TagLabel(tag: tag, name: model.label(tag))
                Spacer()
                if isSelected {
                    // VoiceOver hears the Selected trait instead.
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
            }
        }
        .disabled(!model.canPick(tag))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        // A parent's fold can show its name twice, so tests find the row by this and its label.
        .accessibilityIdentifier(AccessibilityID.tagsTag)
        // The leading edge holds what nests a tag (D4), the trailing one what changes it.
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if model.canAddInside(tag) {
                Button(LocalizedStringResource("Add Inside", bundle: .module), systemImage: "plus") {
                    startAddingInside(tag)
                }
                .tint(.green)
                .accessibilityLabel(Text("Add inside \(tag.name)", bundle: .module))
                .accessibilityIdentifier(AccessibilityID.tagsAddInsideSwipe)
            }
            if model.canMove(tag) {
                Button(
                    LocalizedStringResource("Move", bundle: .module),
                    systemImage: "arrow.up.and.down.and.arrow.left.and.right"
                ) {
                    moving = tag
                }
                .tint(.blue)
                .accessibilityLabel(Text("Move \(tag.name)", bundle: .module))
                .accessibilityIdentifier(AccessibilityID.tagsMove)
            }
        }
        .swipeActions(allowsFullSwipe: false) {
            if !tag.isReadOnly {
                Button(LocalizedStringResource("Archive", bundle: .module), systemImage: "archivebox") {
                    if model.liveChildren(of: tag) > 0 {
                        archiveBlocked = tag
                        isArchiveBlocked = true
                    } else {
                        model.archive(tag)
                    }
                }
                Button(LocalizedStringResource("Rename", bundle: .module), systemImage: "pencil") {
                    renaming = tag
                    newName = tag.name
                    isRenaming = true
                }
                .tint(.indigo)
            }
            if model.canMerge(tag) {
                Button(LocalizedStringResource("Merge", bundle: .module), systemImage: "arrow.triangle.merge") {
                    merging = tag
                }
                .tint(.purple)
                .accessibilityIdentifier(AccessibilityID.tagsMerge)
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

/// A tag's name, or `name` for it, marked if archived, over a piece's details.
struct TagLabel: View {
    let tag: Tag
    let name: String
    /// Off for a row that can't be chosen, which then reads as dimmed.
    @Environment(\.isEnabled) private var isEnabled

    init(tag: Tag, name: String? = nil) {
        self.tag = tag
        self.name = name ?? tag.name
    }

    var body: some View {
        // `Color.primary` and `.secondaryText`, as `.primary` and `.secondary` in a button are its tint.
        VStack(alignment: .leading) {
            HStack {
                Text(name)
                    .foregroundStyle(isEnabled ? AnyShapeStyle(Color.primary) : AnyShapeStyle(.secondaryText))
                if tag.isArchived {
                    Text("Archived", bundle: .module)
                        .foregroundStyle(.secondaryText)
                }
            }
            // This version can't bring it back, so it can't be chosen (#132).
            if tag.isArchived && tag.isReadOnly {
                Text("Archived by a newer version of Pianism. Update to use it.", bundle: .module)
                    .font(.subheadline)
                    .foregroundStyle(.secondaryText)
            }
            if let details = tag.details {
                Text(details)
                    .font(.subheadline)
                    .foregroundStyle(.secondaryText)
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
    /// Tags' names as a list, such as "Ballade No. 1, Scales › D minor", or "Untagged" if there are none (TAG-2, D5).
    init(tagNames names: [String]) {
        if names.isEmpty {
            self.init("Untagged", bundle: .module)
        } else {
            self.init(names.formatted(.list(type: .and, width: .narrow)))
        }
    }
}

// Tagged, so the largest text shows a piece's details under its name.
#Preview("Tagged, dark, AX5") {
    TagPickerView(model: .preview())
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}

#Preview("A tag merged away") {
    let model = TagPickerModel.preview()
    model.merge(model.shown(.piece)[1], into: model.shown(.piece)[0])
    return TagPickerView(model: model)
}

#Preview("A skill inside Scales, chosen") {
    let model = TagPickerModel.preview()
    model.toggle(model.shown(inside: BuiltInSkill.scales.tag)[0])
    return TagPickerView(model: model)
}

#Preview("Adding") {
    TagPickerView(model: .preview(query: "Nocturne"))
}
