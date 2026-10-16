import PianismCore
import SwiftUI

/// The Practice screen: one tap to start, the time always visible (SES-1, SES-2, P1).
struct PracticeView: View {
    @Bindable var model: PracticeModel

    @ScaledMetric(relativeTo: .largeTitle) private var timeSize = 76
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text(status, bundle: .module)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(AccessibilityID.practiceStatus)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let elapsed = model.session?.elapsed(at: model.clock.now) ?? 0
                Text(ElapsedTime.display(elapsed))
                    .font(.system(size: timeSize * timeScale, weight: .light, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityLabel(Text("Practice time", bundle: .module))
                    .accessibilityValue(ElapsedTime.spoken(elapsed))
                    .accessibilityIdentifier(AccessibilityID.practiceElapsed)
            }
            if model.session == nil, let last = model.lastSession {
                let duration = ElapsedTime.display(last.elapsed(at: model.clock.now))
                Text("Last session: \(duration)", bundle: .module)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(AccessibilityID.practiceLastSession)
            }
            if model.waitingCount > 0 {
                Text("^[\(model.waitingCount) session](inflect: true) waiting to be saved", bundle: .module)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(AccessibilityID.practiceWaiting)
            }
            Spacer()
            controls
        }
        .padding(24)
        .frame(maxWidth: 560)
        .alert(Text("Couldn't save that change", bundle: .module), isPresented: $model.isShowingStorageError) {
            Button(role: .cancel) {
            } label: {
                Text("OK", bundle: .module)
            }
        } message: {
            Text("Pianism couldn't reach its storage. Try again in a moment.", bundle: .module)
        }
    }

    @ViewBuilder private var controls: some View {
        switch model.session?.state {
        case nil, .ended:
            CommandButton("Start", systemImage: "play.fill", id: AccessibilityID.practiceStart, prominent: true) {
                model.start()
            }
        case .running:
            HStack(spacing: 16) {
                CommandButton("Pause", systemImage: "pause.fill", id: AccessibilityID.practicePause) {
                    model.pause()
                }
                CommandButton("Stop", systemImage: "stop.fill", id: AccessibilityID.practiceStop, prominent: true) {
                    model.stop()
                }
            }
        case .paused:
            HStack(spacing: 16) {
                CommandButton("Resume", systemImage: "play.fill", id: AccessibilityID.practiceResume) {
                    model.resume()
                }
                CommandButton("Stop", systemImage: "stop.fill", id: AccessibilityID.practiceStop, prominent: true) {
                    model.stop()
                }
            }
        }
    }

    /// Larger on iPad, which often sits on a music stand, read from the bench.
    private var timeScale: CGFloat {
        sizeClass == .regular ? 1.8 : 1
    }

    private var status: LocalizedStringKey {
        switch model.session?.state {
        case nil, .ended: "Ready to practice"
        case .running: "Practicing"
        case .paused: "Paused"
        }
    }
}

/// A full-width, extra-large button for the screen's main commands.
private struct CommandButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let id: String
    let prominent: Bool
    let action: () -> Void

    /// Takes the title unlabeled, like SwiftUI's own `Button` and `Label`.
    init(
        _ title: LocalizedStringKey, systemImage: String, id: String, prominent: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.id = id
        self.prominent = prominent
        self.action = action
    }

    var body: some View {
        Group {
            if prominent {
                button.buttonStyle(.borderedProminent)
            } else {
                button.buttonStyle(.bordered)
            }
        }
        .controlSize(.extraLarge)
        .accessibilityIdentifier(id)
    }

    private var button: some View {
        Button(action: action) {
            Label {
                Text(title, bundle: .module)
            } icon: {
                Image(systemName: systemImage)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview("Ready") {
    PracticeView(model: .preview(.ready))
}

#Preview("Practicing") {
    PracticeView(model: .preview(.running))
}

#Preview("Paused, dark, AX5") {
    PracticeView(model: .preview(.paused))
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
