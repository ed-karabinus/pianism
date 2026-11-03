import SwiftUI

/// The Settings tab: connecting a piano (MIDI-2), when Practice asks "Still practicing?" and stops a session (SES-3,
/// SES-4), and the overlap warning (SES-5) for now; SET-1's other settings join it one section at a time.
struct SettingsView: View {
    @Bindable var practice: PracticeModel

    @AppStorage(SettingsKey.showsOverlapWarning) private var showsOverlapWarning = true

    var body: some View {
        NavigationStack {
            Form {
                let pianos = practice.connectedPianos
                Section {
                    NavigationLink {
                        ConnectPianoView(pianos: pianos)
                    } label: {
                        if pianos.isEmpty {
                            Text("Connect a piano", bundle: .module)
                        } else {
                            Text("\(pianos.formatted(.list(type: .and))) connected", bundle: .module)
                        }
                    }
                    .accessibilityIdentifier(AccessibilityID.settingsPianos)
                } header: {
                    Text("Piano", bundle: .module)
                }
                Section {
                    Picker(selection: $practice.nudge) {
                        times(practice.nudgeChoices)
                    } label: {
                        Text("Ask “Still practicing?” after", bundle: .module)
                    }
                    .accessibilityIdentifier(AccessibilityID.settingsNudge)
                    Picker(selection: $practice.cap) {
                        times(practice.capChoices)
                    } label: {
                        Text("Stop a session left running after", bundle: .module)
                    }
                    .disabled(!practice.canChangeCap)
                    .accessibilityIdentifier(AccessibilityID.settingsCap)
                } header: {
                    Text("Practice", bundle: .module)
                } footer: {
                    if !practice.canChangeCap {
                        Text("You can change when a session stops once this one ends.", bundle: .module)
                    }
                }
                Section {
                    Toggle(isOn: $showsOverlapWarning) {
                        Text("Overlap warning", bundle: .module)
                    }
                    .accessibilityIdentifier(AccessibilityID.settingsOverlapWarning)
                } header: {
                    Text("History", bundle: .module)
                } footer: {
                    Text(
                        "Warns when a session you add or edit shares practice time with another. The day's total counts that time twice.",
                        bundle: .module)
                }
            }
            .navigationTitle(Text("Settings", bundle: .module))
        }
    }

    private func times(_ choices: [TimeInterval]) -> some View {
        ForEach(choices, id: \.self) { Text(ElapsedTime.spoken($0)).tag($0) }
    }
}

#Preview("No piano") {
    SettingsView(practice: .preview(.ready))
}

#Preview("A session running, a piano, dark, AX5") {
    let practice = PracticeModel.preview(.running)
    practice.connectedPianos = ["MIDI KEYBOARD"]
    return SettingsView(practice: practice)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
