import CoreAudioKit
import SwiftUI

/// Which pianos Pianism hears, how to connect one over USB, and Apple's screen for pairing one over Bluetooth (MIDI-2).
/// Opened from Settings (SET-1).
struct ConnectPianoView: View {
    let practice: PracticeModel

    var body: some View {
        Form {
            Section {
                if let piano = practice.missingBluetoothPiano {
                    Text("\(piano) isn't connected", bundle: .module)
                        .accessibilityIdentifier(AccessibilityID.pianosMissing)
                    #if os(iOS)
                        NavigationLink {
                            PairingScreen(practice: practice)
                        } label: {
                            Text("Reconnect", bundle: .module)
                        }
                        .accessibilityIdentifier(AccessibilityID.pianosReconnect)
                    #endif
                    Button(role: .destructive, action: practice.forgetBluetoothPiano) {
                        Text("Forget This Piano", bundle: .module)
                    }
                    .accessibilityIdentifier(AccessibilityID.pianosForget)
                } else if practice.connectedPianos.isEmpty {
                    Text("No piano connected", bundle: .module)
                }
                ForEach(practice.connectedPianos, id: \.self) { Text($0) }
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
                        PairingScreen(practice: practice)
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
    }
}

#if os(iOS)
    /// Apple's pairing screen, titled, telling `practice` while it's open so it knows a piano that shows up then as a
    /// Bluetooth one (MIDI-2).
    struct PairingScreen: View {
        let practice: PracticeModel
        /// Apple's screen is made only while this is on screen, so each time it comes back it searches afresh: left
        /// open in another tab, it kept spinning on "No devices found" (the owner's device check, 2026-11-11).
        @State private var isShown = false

        var body: some View {
            ZStack {
                if isShown { BluetoothPairingView() }
            }
            .navigationTitle(Text("Bluetooth", bundle: .module))
            // A UIKit list doesn't collapse a large title, which would crowd Apple's short list.
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                isShown = true
                practice.isPairing = true
            }
            .onDisappear {
                isShown = false
                practice.isPairing = false
            }
        }
    }

    /// Apple's screen that finds Bluetooth MIDI devices nearby and pairs them, which CoreMIDI then hears.
    private struct BluetoothPairingView: UIViewControllerRepresentable {
        func makeUIViewController(context _: Context) -> CABTMIDICentralViewController {
            let controller = CABTMIDICentralViewController()
            // On iOS 27.0, the screen's own `loadView` crashes building its list with a height of NaN (Apple's bug,
            // FB25301268, reported fixed in 27.2). This is Apple's workaround from its developer forums: giving it a
            // list skips `loadView`, and `viewDidLoad` is what starts the search for pianos.
            if #available(iOS 27, *) {
                if #unavailable(iOS 27.2) {
                    controller.tableView = UITableView(frame: .zero, style: .grouped)
                    controller.viewDidLoad()
                }
            }
            return controller
        }

        func updateUIViewController(_: CABTMIDICentralViewController, context _: Context) {}
    }
#endif

#Preview("A piano") {
    NavigationStack { ConnectPianoView(practice: .preview(freeUsed: 0)) }
}

#Preview("A Bluetooth piano gone") {
    NavigationStack { ConnectPianoView(practice: .preview(.bluetoothMissing)) }
}

#Preview("None, dark, AX5") {
    NavigationStack { ConnectPianoView(practice: .preview(.ready)) }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
