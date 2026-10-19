import PianismCore
import SwiftUI

/// The Practice screen: one tap to start, the time always visible (SES-1, SES-2, P1).
struct PracticeView: View {
    @Bindable var model: PracticeModel
    let tags: TagPickerModel
    /// Opens a finished session's editor, from the banner of one that ended itself at the cap (SES-4).
    let edit: (PracticeSession) -> Void

    @State private var isPickingTags = false

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
                if model.lastSessionReachedCap {
                    capBanner(last)
                } else {
                    let duration = ElapsedTime.display(last.elapsed(at: model.clock.now))
                    Text("Last session: \(duration)", bundle: .module)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier(AccessibilityID.practiceLastSession)
                }
            }
            if model.waitingCount > 0 {
                Text("^[\(model.waitingCount) session](inflect: true) waiting to be saved", bundle: .module)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier(AccessibilityID.practiceWaiting)
            }
            Spacer()
            if model.session?.state == .running || model.session?.state == .paused {
                tagsButton
            }
            controls
        }
        .padding(24)
        .frame(maxWidth: 560)
        .sheet(isPresented: $isPickingTags) {
            // Tagging stores the session, so its failure shows over the picker, which covers this screen.
            TagPickerView(model: tags)
                .storageAlert(Text(storageErrorTitle, bundle: .module), isPresented: $model.isShowingStorageError)
        }
        .storageAlert(Text(storageErrorTitle, bundle: .module), isPresented: $model.isShowingStorageError)
        // Ends the session at the cap while the app stays open, as on an iPad on a music stand. Otherwise it ends
        // when the app next opens (SES-4).
        .task(id: model.session) {
            guard let end = model.session?.whenPracticeReaches(model.cap),
                (try? await Task.sleep(for: .seconds(end.timeIntervalSince(model.clock.now)))) != nil
            else { return }
            model.refresh()
        }
    }

    /// Says the last session ended itself at the cap, and offers to fix it in History (SES-4).
    private func capBanner(_ session: PracticeSession) -> some View {
        VStack(alignment: .trailing, spacing: 12) {
            let cap = ElapsedTime.spoken(model.cap)
            Text(
                "Pianism stopped your session at \(cap) of practice, in case the timer was left running.",
                bundle: .module
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(AccessibilityID.practiceCapped)
            Button(LocalizedStringResource("Edit", bundle: .module)) {
                model.dismissCapBanner()
                edit(session)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(Text("Edit Session", bundle: .module))
            .accessibilityIdentifier(AccessibilityID.practiceCappedEdit)
        }
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }

    /// The session's pieces and skills, which opens the tag picker (TAG-2).
    private var tagsButton: some View {
        Button {
            isPickingTags = true
        } label: {
            Label {
                tags.selected.isEmpty ? Text("Add tags", bundle: .module) : Text(tags: tags.selected)
            } icon: {
                Image(systemName: "tag")
            }
            .lineLimit(2)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(Text("Tags", bundle: .module))
        .accessibilityValue(Text(tags: tags.selected))
        .accessibilityIdentifier(AccessibilityID.practiceTags)
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

    private let storageErrorTitle: LocalizedStringKey = "Couldn't save that change"

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

extension View {
    /// Says that Pianism couldn't reach its storage, under `title`.
    func storageAlert(_ title: Text, isPresented: Binding<Bool>) -> some View {
        alert(title, isPresented: isPresented) {
        } message: {
            Text("Pianism couldn't reach its storage. Try again in a moment.", bundle: .module)
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
    let model = PracticeModel.preview(.ready)
    PracticeView(model: model, tags: .preview(for: model)) { _ in }
}

#Preview("Practicing, tagged") {
    let model = PracticeModel.preview(.running)
    PracticeView(model: model, tags: .preview(for: model)) { _ in }
}

#Preview("Paused, dark, AX5") {
    let model = PracticeModel.preview(.paused)
    PracticeView(model: model, tags: .preview(for: model)) { _ in }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}

#Preview("Stopped at the cap") {
    let model = PracticeModel.preview(.capped)
    PracticeView(model: model, tags: .preview(for: model)) { _ in }
}

#Preview("Stopped at the cap, dark, AX5") {
    let model = PracticeModel.preview(.capped)
    PracticeView(model: model, tags: .preview(for: model)) { _ in }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
