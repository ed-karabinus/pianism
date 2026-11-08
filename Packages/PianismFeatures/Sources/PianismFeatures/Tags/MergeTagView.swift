import PianismCore
import SwiftUI

/// Merges a piece or skill into another of its kind, chosen here, which its sessions then count toward (TAG-4).
struct MergeTagView: View {
    let tag: Tag
    let model: TagPickerModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.mergeTargets(for: tag)) { kept in
                        Button {
                            model.merge(tag, into: kept)
                            dismiss()
                        } label: {
                            TagLabel(tag: kept)
                        }
                        .accessibilityIdentifier(AccessibilityID.mergeTarget)
                    }
                } header: {
                    Text("Merge into", bundle: .module)
                } footer: {
                    Text(
                        "Sessions tagged “\(tag.name)” will count toward the one you choose. You can undo this at any time, under Merged at the end of your tags.",
                        bundle: .module)
                }
            }
            .navigationTitle(Text("Merge “\(tag.name)”", bundle: .module))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
            }
        }
    }
}

#Preview("Pieces") {
    let model = TagPickerModel.preview()
    MergeTagView(tag: model.shown(.piece)[0], model: model)
}

#Preview("Dark, AX5") {
    let model = TagPickerModel.preview()
    MergeTagView(tag: model.shown(.piece)[0], model: model)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
