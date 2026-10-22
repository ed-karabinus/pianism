import PianismCore
import SwiftUI

/// Gives a piece a composer and a target tempo (TAG-3).
struct PieceDetailsView: View {
    let tag: Tag
    let model: TagPickerModel

    @Environment(\.dismiss) private var dismiss
    @State private var composer: String
    @State private var tempo: String

    init(tag: Tag, model: TagPickerModel) {
        self.tag = tag
        self.model = model
        _composer = State(initialValue: tag.composer)
        _tempo = State(initialValue: tag.targetTempo.map(String.init) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Labelled rows, so the labels stay once the fields are filled in.
                    LabeledContent {
                        TextField(text: $composer, prompt: Text("None", bundle: .module)) {
                            Text("Composer", bundle: .module)
                        }
                        .multilineTextAlignment(.trailing)
                        .accessibilityIdentifier(AccessibilityID.detailsComposer)
                    } label: {
                        Text("Composer", bundle: .module)
                    }
                    LabeledContent {
                        TextField(text: $tempo, prompt: Text("None", bundle: .module)) {
                            Text("Target tempo (BPM)", bundle: .module)
                        }
                        .multilineTextAlignment(.trailing)
                        // macOS, where the feature tests run, has no number pad.
                        #if os(iOS)
                            .keyboardType(.numberPad)
                        #endif
                        .accessibilityIdentifier(AccessibilityID.detailsTempo)
                    } label: {
                        Text("Target tempo (BPM)", bundle: .module)
                    }
                } footer: {
                    if !model.canSetDetails(tempo: tempo) {
                        let range = TagPickerModel.targetTempos
                        Text(
                            "A target tempo is a whole number from \(range.lowerBound) to \(range.upperBound).",
                            bundle: .module)
                    }
                }
            }
            .navigationTitle(tag.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) {
                        model.setDetails(tag, composer: composer, tempo: tempo)
                        dismiss()
                    }
                    .disabled(!model.canSetDetails(tempo: tempo))
                    .accessibilityIdentifier(AccessibilityID.detailsSave)
                }
            }
        }
    }
}

#Preview("Filled in") {
    let model = TagPickerModel.preview()
    PieceDetailsView(tag: model.shown(.piece)[0], model: model)
}

#Preview("Empty, dark, AX5") {
    let model = TagPickerModel.preview()
    PieceDetailsView(tag: model.shown(.piece)[1], model: model)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
