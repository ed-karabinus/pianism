import SwiftUI

/// The Settings tab: connecting a piano (MIDI-2) and the overlap warning (SES-5) for now; SET-1's other settings
/// join it one section at a time.
struct SettingsView: View {
    let pianos: [String]

    @AppStorage(SettingsKey.showsOverlapWarning) private var showsOverlapWarning = true

    var body: some View {
        NavigationStack {
            Form {
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
                    Toggle(isOn: $showsOverlapWarning) {
                        Text("Overlap warning", bundle: .module)
                    }
                    .accessibilityIdentifier(AccessibilityID.settingsOverlapWarning)
                } header: {
                    Text("History", bundle: .module)
                } footer: {
                    Text(
                        "When a session you edit or add shares practice time with another, say so, as the day's total counts it twice.",
                        bundle: .module)
                }
            }
            .navigationTitle(Text("Settings", bundle: .module))
        }
    }
}

/// The keys under which settings are kept on this device, in the app's own defaults (SET-1, decided with Ed,
/// 2026-11-02). A key's name is permanent: renaming one loses what was set under it.
enum SettingsKey {
    /// Kept since SES-5 by the editor's "Don't show again".
    static let showsOverlapWarning = "showsOverlapWarning"
}

#Preview("No piano") {
    SettingsView(pianos: [])
}

#Preview("A piano, dark, AX5") {
    SettingsView(pianos: ["MIDI KEYBOARD"])
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
