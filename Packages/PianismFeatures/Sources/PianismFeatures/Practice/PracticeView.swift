import PianismCore
import SwiftUI

/// The Practice screen: one tap to start, the time always visible (SES-1, SES-2, P1).
struct PracticeView: View {
    @Bindable var model: PracticeModel
    let tags: TagPickerModel
    /// Opens the editor of the session with this ID, from the banner of one that ended itself at the cap (SES-4).
    let edit: (UUID) -> Void

    @State private var isPickingTags = false
    /// The session as it was when "I Stopped Earlier" was tapped, while its end is picked, and the end picked so
    /// far (SES-3). Keyed by the whole session, so a pause, a resume or a session stopped another way goes back
    /// to the question rather than keeping an end from before. The date isn't optional: a binding unwrapping one
    /// traps if the picker reads it after it's cleared.
    @State private var pickingEndOf: PracticeSession?
    @State private var stoppedAt = Date.distantPast
    /// The session whose "Still practicing?" was answered, so it's asked once per session (SES-3).
    @AppStorage("stillPracticingAnswered") private var answeredSessionID = ""

    @ScaledMetric(relativeTo: .largeTitle) private var timeSize = 76
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        // When Practice doesn't fit, as with the end being picked (SES-3), the time shrinks first, then Practice
        // scrolls, as at the largest text sizes.
        ViewThatFits(in: .vertical) {
            content()
            content(compactTime: true)
            ScrollView { content(compactTime: true).frame(maxWidth: .infinity) }
        }
        .sheet(isPresented: $isPickingTags) {
            // Tagging stores the session, so its failure shows over the picker, which covers this screen.
            TagPickerView(model: tags)
                .storageAlert(Text(storageErrorTitle, bundle: .module), isPresented: $model.isShowingStorageError)
        }
        .storageAlert(Text(storageErrorTitle, bundle: .module), isPresented: $model.isShowingStorageError)
        // Asks "Still practicing?" and ends the session at the cap while Practice is on screen, as on an iPad on a
        // music stand. Otherwise that happens when Practice or the app next appears (SES-3, SES-4).
        .task(id: model.session) {
            while let next = model.nextRefresh,
                (try? await Task.sleep(for: .seconds(next.timeIntervalSince(model.clock.now)))) != nil
            {
                model.refresh()
            }
        }
    }

    /// Everything on Practice, spread to fill the screen when it fits. With `compactTime`, the time is half its
    /// size.
    private func content(compactTime: Bool = false) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Text(status, bundle: .module)
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(AccessibilityID.practiceStatus)
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                let elapsed = model.session?.elapsed(at: model.clock.now) ?? 0
                Text(ElapsedTime.display(elapsed))
                    .font(
                        .system(size: timeSize * timeScale * (compactTime ? 0.5 : 1), weight: .light, design: .rounded)
                            .monospacedDigit()
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityLabel(Text("Practice time", bundle: .module))
                    .accessibilityValue(ElapsedTime.spoken(elapsed))
                    .accessibilityIdentifier(AccessibilityID.practiceElapsed)
            }
            if let session = model.session, model.isPastNudge, answeredSessionID != session.id.uuidString {
                stillPracticingBanner(session)
            }
            if model.session == nil, let last = model.lastSession {
                if model.lastSessionReachedCap {
                    capBanner(last.id)
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
    }

    /// Asks whether the session is still going, once its practice passes the nudge, and takes the real end if
    /// it isn't (SES-3).
    private func stillPracticingBanner(_ session: PracticeSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Still practicing?", bundle: .module)
                .font(.headline)
                .accessibilityIdentifier(AccessibilityID.practiceStillPracticing)
            if pickingEndOf == session {
                // The upper bound never falls below the lower, as a ClosedRange traps then, should the clock step
                // back.
                DatePicker(selection: $stoppedAt, in: session.latestEvent...max(session.latestEvent, model.clock.now)) {
                    Text("Stopped at", bundle: .module)
                }
                // Wheels, shown at once, as the end is what "I Stopped Earlier" was tapped to set. macOS, where
                // the package's tests run, has none.
                #if os(iOS)
                    .datePickerStyle(.wheel)
                #endif
                // VoiceOver still reads the label. iPad showed it beside the wheels, where it broke mid-word at
                // the largest text sizes.
                .labelsHidden()
                .accessibilityIdentifier(AccessibilityID.practiceStoppedAt)
            }
            ViewThatFits {
                HStack { stillPracticingAnswers(session) }
                VStack(alignment: .leading) { stillPracticingAnswers(session) }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bannerStyle()
    }

    /// "Still Practicing" stays while the end is picked, as the way back from a mistaken "I Stopped Earlier".
    @ViewBuilder private func stillPracticingAnswers(_ session: PracticeSession) -> some View {
        if pickingEndOf == session {
            Button(LocalizedStringResource("Stop at This Time", bundle: .module)) {
                // The wheels show the picked end clamped to the range, so stop there too.
                model.stop(at: max(stoppedAt, session.latestEvent))
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(AccessibilityID.practiceStopAt)
        }
        Button(LocalizedStringResource("Still Practicing", bundle: .module)) {
            answeredSessionID = session.id.uuidString
        }
        .accessibilityIdentifier(AccessibilityID.practiceStillPracticingYes)
        if pickingEndOf != session {
            Button(LocalizedStringResource("I Stopped Earlier", bundle: .module)) {
                stoppedAt = model.clock.now
                pickingEndOf = session
            }
            .accessibilityIdentifier(AccessibilityID.practiceStoppedEarlier)
        }
    }

    /// A Pause or Resume once practice has passed the nudge shows the user is there, so it answers "Still
    /// practicing?" for the session (SES-3).
    private func answerIfPastNudge() {
        if let session = model.session, session.elapsed(at: model.clock.now) >= model.nudge {
            answeredSessionID = session.id.uuidString
        }
    }

    /// Says the last session ended itself at the cap, and offers to fix it in History (SES-4).
    private func capBanner(_ id: UUID) -> some View {
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
                edit(id)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(Text("Edit Session", bundle: .module))
            .accessibilityIdentifier(AccessibilityID.practiceCappedEdit)
        }
        .bannerStyle()
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
                    answerIfPastNudge()
                    model.pause()
                }
                CommandButton("Stop", systemImage: "stop.fill", id: AccessibilityID.practiceStop, prominent: true) {
                    model.stop()
                }
            }
        case .paused:
            HStack(spacing: 16) {
                CommandButton("Resume", systemImage: "play.fill", id: AccessibilityID.practiceResume) {
                    answerIfPastNudge()
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
    /// A card for a banner on Practice (SES-3, SES-4).
    fileprivate func bannerStyle() -> some View {
        padding().background(.regularMaterial, in: .rect(cornerRadius: 16))
    }

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

#Preview("Still practicing?") {
    let model = PracticeModel.preview(.pastNudge)
    PracticeView(model: model, tags: .preview(for: model)) { _ in }
}

#Preview("Still practicing?, dark, AX5") {
    let model = PracticeModel.preview(.pastNudge)
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
