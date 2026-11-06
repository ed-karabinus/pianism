import SwiftUI

/// What Pianism does, shown once to someone with no practice yet, with two ways on (ONB-1).
struct WelcomeView: View {
    let practice: PracticeModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            // At the largest text sizes it doesn't fit, so all of it scrolls, as Practice does.
            ViewThatFits(in: .vertical) {
                VStack {
                    words
                    Spacer(minLength: 0)
                    actions
                }
                .padding()
                ScrollView {
                    VStack {
                        words
                        actions
                    }
                    .padding()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                        .accessibilityIdentifier(AccessibilityID.welcomeClose)
                }
            }
        }
    }

    private var words: some View {
        VStack(spacing: 20) {
            Image(systemName: "pianokeys")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Pianism", bundle: .module)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text(
                "Time your practice with one tap, tag what you worked on, and see your week build up.",
                bundle: .module)
            Text(
                "Connect a digital piano and sessions can start themselves while Pianism is open.",
                bundle: .module
            )
            .accessibilityIdentifier(AccessibilityID.welcomeWords)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                // Closes first: if storage refuses the session, Practice's alert can't show over this sheet.
                dismiss()
                practice.start()
            } label: {
                Text("Start your first session", bundle: .module).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier(AccessibilityID.welcomeStart)
            NavigationLink {
                ConnectPianoView(pianos: practice.connectedPianos)
            } label: {
                Text("Connect a piano", bundle: .module)
            }
            .accessibilityIdentifier(AccessibilityID.welcomeConnect)
        }
    }
}

#Preview {
    WelcomeView(practice: .preview(.ready))
}

#Preview("Dark") {
    WelcomeView(practice: .preview(.ready))
        .preferredColorScheme(.dark)
}

#Preview("AX5") {
    WelcomeView(practice: .preview(.ready))
        .dynamicTypeSize(.accessibility5)
}
