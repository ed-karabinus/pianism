import PianismCore
import SwiftUI

/// Moves a piece or skill inside another of its kind, chosen here, or back to the top level. Its sessions follow it
/// (TAG-5, D4). Where it is now is checked, and a place that already has a tag of its name says so instead (Q1).
struct MoveTagView: View {
    let tag: Tag
    let model: TagPickerModel

    @Environment(\.dismiss) private var dismiss
    @State private var refusal: String?
    @State private var isRefused = false

    var body: some View {
        let current = model.parent(of: tag)
        NavigationStack {
            List {
                // Its own section, so a user's tag named "Top level" can't be mistaken for it.
                Section {
                    row(to: nil, isCurrent: current == nil) {
                        Label {
                            Text("Top level", bundle: .module)
                                .foregroundStyle(Color.primary)
                        } icon: {
                            Image(systemName: "arrow.up.to.line")
                        }
                    }
                    .accessibilityIdentifier(AccessibilityID.moveTopLevel)
                }
                Section {
                    ForEach(model.moveTargets(for: tag)) { parent in
                        row(to: parent, isCurrent: parent.id == current?.id) {
                            TagLabel(tag: parent)
                        }
                        .accessibilityIdentifier(AccessibilityID.moveTarget)
                    }
                } header: {
                    tag.kind == .piece
                        ? Text("Inside a piece", bundle: .module) : Text("Inside a skill", bundle: .module)
                }
            }
            .navigationTitle(Text("Move “\(tag.name)”", bundle: .module))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
            }
            // Nothing is written: the sheet stays open, to choose another place or cancel (Q1).
            .alert(Text(refusal ?? ""), isPresented: $isRefused) {}
        }
    }

    /// A place to move to, checked if `tag` is there now, which choosing leaves as it is.
    private func row(to parent: Tag?, isCurrent: Bool, @ViewBuilder label: () -> some View) -> some View {
        Button {
            if isCurrent {
                dismiss()
            } else if let reason = model.moveRefusal(tag, to: parent) {
                refusal = reason
                isRefused = true
            } else {
                model.move(tag, to: parent)
                dismiss()
            }
        } label: {
            HStack {
                label()
                Spacer()
                if isCurrent {
                    // VoiceOver hears the Selected trait instead.
                    Image(systemName: "checkmark")
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

#Preview("A skill inside Scales") {
    let model = TagPickerModel.preview()
    MoveTagView(tag: model.shown(inside: BuiltInSkill.scales.tag)[0], model: model)
}

#Preview("A piece, dark, AX5") {
    let model = TagPickerModel.preview()
    MoveTagView(tag: model.shown(.piece)[0], model: model)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
