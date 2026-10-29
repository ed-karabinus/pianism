import CoreAudioKit
import SwiftUI

/// Which pianos Pianism hears, how to connect one over USB, and Apple's screen for pairing one over Bluetooth (MIDI-2).
struct ConnectPianoView: View {
    let pianos: [String]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if pianos.isEmpty {
                        Text("No piano connected", bundle: .module)
                    }
                    ForEach(pianos, id: \.self) { Text($0) }
                } header: {
                    Text("Connected", bundle: .module)
                }
                Section {
                    Text("Connect the cable to your piano's USB port and to this device.", bundle: .module)
                    // The Kawai CA59 sent nothing until the cable was plugged in at its own end (device checks,
                    // 2026-10-28, and row 5 on the Mac).
                    Text(
                        "If your piano doesn't show up, unplug the cable at the piano's end and plug it back in.",
                        bundle: .module
                    )
                    .accessibilityIdentifier(AccessibilityID.pianosReplug)
                    // The CA59 turns Bluetooth MIDI on at every power-on, and USB is quiet while it's connected.
                    Text(
                        "If it still doesn't show up, turn off Bluetooth MIDI on the piano: many pianos stay quiet over USB while it's connected.",
                        bundle: .module)
                } header: {
                    Text("USB", bundle: .module)
                }
                Section {
                    // Apple's pairing screen, which the simulator and macOS, where the feature tests run, can't show.
                    #if os(iOS)
                        NavigationLink {
                            BluetoothPairingView()
                                .navigationTitle(Text("Bluetooth", bundle: .module))
                                // A UIKit list doesn't collapse a large title, which would crowd Apple's short list.
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            Text("Pair a Bluetooth piano", bundle: .module)
                        }
                        .accessibilityIdentifier(AccessibilityID.pianosPair)
                    #endif
                } header: {
                    Text("Bluetooth", bundle: .module)
                } footer: {
                    Text(
                        "A piano connects to one device at a time, so disconnect it from any other first.",
                        bundle: .module)
                }
            }
            .navigationTitle(Text("Connect a piano", bundle: .module))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .confirm) { dismiss() }
                        .accessibilityIdentifier(AccessibilityID.pianosDone)
                }
            }
        }
    }
}

#if os(iOS)
    /// Apple's screen that finds Bluetooth MIDI devices nearby and pairs them, which CoreMIDI then hears.
    private struct BluetoothPairingView: UIViewControllerRepresentable {
        func makeUIViewController(context _: Context) -> CABTMIDICentralViewController {
            CABTMIDICentralViewController()
        }

        func updateUIViewController(_: CABTMIDICentralViewController, context _: Context) {}
    }
#endif

#Preview("A piano") {
    ConnectPianoView(pianos: ["MIDI KEYBOARD"])
}

#Preview("None, dark, AX5") {
    ConnectPianoView(pianos: [])
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
