import PianismCore
import SwiftUI

/// The Practice screen: one tap to start, the time always visible (SES-1, SES-2, P1).
struct PracticeView: View {
    @Bindable var model: PracticeModel
    let tags: TagPickerModel
    /// Opens the Pro screen, from the line saying the free piano sessions are used (PRO-2).
    var showPro: () -> Void = {}
    /// Opens the editor of the session with this ID, from the banner of one that ended itself at the cap (SES-4).
    let edit: (UUID) -> Void

    @State private var isPickingTags = false
    /// The session as it was when "I stopped earlier" was tapped, while its end is picked, and the end picked so
    /// far (SES-3). Keyed by the whole session, so a pause, a resume or a session stopped another way goes back
    /// to the question rather than keeping an end from before. The date isn't optional: a binding unwrapping one
    /// traps if the picker reads it after it's cleared.
    @State private var pickingEndOf: PracticeSession?
    @State private var stoppedAt = Date.distantPast
    /// The pop-up saying a session wasn't saved, for 4 s (SES-1, MIDI-1), and which one it's for, so the next one
    /// gets its own 4 s.
    @State private var notSavedPopUp: NotSaved?
    @State private var notSavedPopUpCount = 0

    @ScaledMetric(relativeTo: .largeTitle) private var timeSize = 76
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        // A piano's session often ends after a silence, with nobody looking, so the line under Start stays too.
        .overlay(alignment: .top) {
            if let notSavedPopUp, model.notSaved != nil {
                Text(notSavedPopUp.message)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .accessibilityIdentifier(AccessibilityID.practiceNotSavedPopUp)
                    // Taps go through to whatever it covers.
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: model.notSavedCount) { _, count in
            withAnimation(.smooth) { notSavedPopUp = model.notSaved }
            notSavedPopUpCount = count
        }
        .task(id: notSavedPopUpCount) {
            guard notSavedPopUp != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth) { notSavedPopUp = nil }
        }
        .onAppear { model.refresh() }
        // The notification's "I stopped earlier" opens Practice with the end being picked (SES-3).
        .onChange(of: model.nudgeOpened, initial: true) { _, opened in
            guard let opened else { return }
            if opened.pickingEnd, let session = model.session, session.id == opened.sessionID {
                pickEnd(of: session)
            }
            model.nudgeOpened = nil
        }
    }

    /// Everything on Practice, spread to fill the screen when it fits. With `compactTime`, the time is half its
    /// size.
    private func content(compactTime: Bool = false) -> some View {
        VStack(spacing: 24) {
            Spacer()
            // The status changes with the time, as a silence that pauses a MIDI session changes both at once.
            TimelineView(PracticeTimelineSchedule(isCounting: model.isCounting)) { _ in
                let now = model.clock.now
                let elapsed = model.elapsed(at: now)
                let pausedAtLastNote = model.isPausedAtLastNote(at: now)
                VStack(spacing: 24) {
                    Text(status(at: now), bundle: .module)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(.secondaryText)
                        .accessibilityIdentifier(AccessibilityID.practiceStatus)
                    Text(ElapsedTime.display(elapsed))
                        .contentTransition(.numericText(value: elapsed))
                        .font(
                            .system(
                                size: timeSize * timeScale * (compactTime ? 0.5 : 1), weight: .light, design: .rounded
                            )
                            .monospacedDigit()
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .accessibilityLabel(Text("Practice time", bundle: .module))
                        .accessibilityValue(ElapsedTime.spoken(elapsed))
                        .accessibilityIdentifier(AccessibilityID.practiceElapsed)
                }
                // When a silence pauses a MIDI session, the time rolls back to the last note as the status changes, so
                // the drop reads as deliberate. Keyed to the pause, so each second's change doesn't roll, and only on
                // the way in; with Reduce Motion the time just changes (#139, decided with Ed, 2026-10-29).
                .animation(
                    pausedAtLastNote && !reduceMotion ? .smooth(duration: 0.8) : nil, value: pausedAtLastNote)
            }
            if let session = model.session, model.isAskingStillPracticing {
                stillPracticingBanner(session)
            }
            if model.session == nil, let notSaved = model.notSaved {
                Text(notSaved.message)
                    .font(.callout)
                    .foregroundStyle(.secondaryText)
                    .accessibilityIdentifier(AccessibilityID.practiceTooShort)
            } else if model.session == nil, let last = model.lastSession {
                if model.lastSessionReachedCap {
                    capBanner(last)
                } else {
                    let duration = ElapsedTime.display(last.elapsed(at: model.clock.now))
                    Text("Last session: \(duration)", bundle: .module)
                        .font(.callout)
                        .foregroundStyle(.secondaryText)
                        .accessibilityIdentifier(AccessibilityID.practiceLastSession)
                }
            }
            if model.waitingCount > 0 {
                Text("^[\(model.waitingCount) session](inflect: true) waiting to be saved", bundle: .module)
                    .font(.footnote)
                    .foregroundStyle(.secondaryText)
                    .accessibilityIdentifier(AccessibilityID.practiceWaiting)
            }
            // The piano Pianism hears, if any (MIDI-2). Nothing without one: connecting one is in Settings, an option
            // for the many who time their practice without a piano (decided with Ed, 2026-10-28 and 2026-11-02).
            if !model.connectedPianos.isEmpty {
                Text("\(model.connectedPianos.formatted(.list(type: .and))) connected", bundle: .module)
                    .font(.footnote)
                    .foregroundStyle(.secondaryText)
                    .accessibilityIdentifier(AccessibilityID.practicePianos)
            }
            // The free piano sessions, without Pro: how many are left, then where Pro is, never a pop-up (PRO-2, D6).
            if let left = model.freePianoSessionsLeft {
                // The link right under its line, in the tint so it reads as one.
                VStack(spacing: 0) {
                    if left > 0 {
                        Text("^[\(left) free piano session](inflect: true) left", bundle: .module)
                            .foregroundStyle(.secondaryText)
                            .accessibilityIdentifier(AccessibilityID.practiceFreeLeft)
                    } else {
                        Text("Sessions that start themselves are part of Pro.", bundle: .module)
                            .foregroundStyle(.secondaryText)
                            .accessibilityIdentifier(AccessibilityID.practiceFreeUsed)
                        // Footnote-sized, so it's given a target big enough to hit.
                        Button(action: showPro) {
                            Text(verbatim: "Pianism Pro").frame(minWidth: 44, minHeight: 44).contentShape(.rect)
                        }
                        .accessibilityIdentifier(AccessibilityID.practiceShowPro)
                    }
                }
                .font(.footnote)
                .multilineTextAlignment(.center)
            }
            if model.showsLowBattery {
                Label {
                    Text("Low battery. The screen stays on while your piano is connected, so plug in.", bundle: .module)
                } icon: {
                    // Red, as the status bar shows a low battery.
                    Image(systemName: "battery.25percent").foregroundStyle(.red)
                }
                .font(.footnote)
                .foregroundStyle(.secondaryText)
                .accessibilityIdentifier(AccessibilityID.practiceLowBattery)
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
                DatePicker(selection: $stoppedAt, in: model.stopRange(of: session)) {
                    Text("Stopped at", bundle: .module)
                }
                // Wheels, shown at once, as the end is what "I stopped earlier" was tapped to set. macOS, where
                // the package's tests run, has none.
                #if os(iOS)
                    .datePickerStyle(.wheel)
                #endif
                // VoiceOver still reads the label. iPad showed it beside the wheels, where it broke mid-word at
                // the largest text sizes.
                .labelsHidden()
                .accessibilityIdentifier(AccessibilityID.practiceStoppedAt)
            }
            // Side by side whenever they fit the width. By default it checks the height too, which Practice's stack
            // offers differently from one layout pass to the next, so the card was measured with one arrangement
            // and drawn with the other.
            ViewThatFits(in: .horizontal) {
                HStack { stillPracticingAnswers(session) }
                VStack(alignment: .leading) { stillPracticingAnswers(session) }
            }
            .buttonStyle(.bordered)
            // Offered where its use is plain, as Apple advises, and only until asked, as the system asks once.
            if model.canAskForNudges, pickingEndOf != session {
                Button(
                    LocalizedStringResource("Remind me with a notification", bundle: .module), systemImage: "bell"
                ) {
                    Task { await model.askForNudges() }
                }
                .accessibilityIdentifier(AccessibilityID.practiceRemindMe)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .bannerStyle()
        .task { await model.checkNudges() }
    }

    /// "Still practicing" stays while the end is picked, as the way back from a mistaken "I stopped earlier".
    @ViewBuilder private func stillPracticingAnswers(_ session: PracticeSession) -> some View {
        if pickingEndOf == session {
            Button(LocalizedStringResource("Stop at this time", bundle: .module)) {
                model.stop(at: stoppedAt)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(AccessibilityID.practiceStopAt)
        }
        Button(LocalizedStringResource("Still practicing", bundle: .module)) {
            model.answerStillPracticing(for: session.id)
        }
        .accessibilityIdentifier(AccessibilityID.practiceStillPracticingYes)
        if pickingEndOf != session {
            Button(LocalizedStringResource("I stopped earlier", bundle: .module)) {
                pickEnd(of: session)
            }
            .accessibilityIdentifier(AccessibilityID.practiceStoppedEarlier)
        }
    }

    /// Shows the wheels for the session's real end, set to now.
    private func pickEnd(of session: PracticeSession) {
        stoppedAt = model.clock.now
        pickingEndOf = session
    }

    /// Says the last session ended itself at the cap, and offers to fix it in History (SES-4). The cap is the
    /// session's practice time, as Settings may have changed the cap since (SET-1).
    private func capBanner(_ last: PracticeSession) -> some View {
        VStack(alignment: .trailing, spacing: 12) {
            let cap = ElapsedTime.spoken(last.elapsed(at: model.clock.now))
            Text(
                "Pianism stopped your session at \(cap) of practice, in case the timer was left running.",
                bundle: .module
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(AccessibilityID.practiceCapped)
            Button(LocalizedStringResource("Edit", bundle: .module)) {
                model.dismissCapBanner()
                edit(last.id)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(Text("Edit session", bundle: .module))
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
                tags.selected.isEmpty ? Text("Add tags", bundle: .module) : Text(tagNames: tags.selectedNames)
            } icon: {
                Image(systemName: "tag")
            }
            .lineLimit(2)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(Text("Tags", bundle: .module))
        .accessibilityValue(Text(tagNames: tags.selectedNames))
        .accessibilityIdentifier(AccessibilityID.practiceTags)
    }

    @ViewBuilder private var controls: some View {
        switch model.session?.state {
        case nil, .ended:
            CommandButton("Start", systemImage: "play.fill", id: AccessibilityID.practiceStart, prominent: true) {
                model.start()
            }
        case .running:
            commandPair {
                CommandButton("Pause", systemImage: "pause.fill", id: AccessibilityID.practicePause) {
                    model.pause()
                }
                CommandButton("Stop", systemImage: "stop.fill", id: AccessibilityID.practiceStop, prominent: true) {
                    model.stop()
                }
            }
        case .paused:
            commandPair {
                CommandButton("Resume", systemImage: "play.fill", id: AccessibilityID.practiceResume) {
                    model.resume()
                }
                CommandButton("Stop", systemImage: "stop.fill", id: AccessibilityID.practiceStop, prominent: true) {
                    model.stop()
                }
            }
        }
    }

    /// Side by side whenever each name fits its half of the width, and stacked otherwise, as at the larger text
    /// sizes, where side by side broke them mid-word.
    private func commandPair(@ViewBuilder _ buttons: () -> some View) -> some View {
        ViewThatFits(in: .horizontal) {
            EqualWidthRow(spacing: 16) { buttons() }
            VStack(spacing: 16, content: buttons)
        }
    }

    private let storageErrorTitle: LocalizedStringKey = "Couldn't save that change"

    /// Larger on iPad, which often sits on a music stand, read from the bench.
    private var timeScale: CGFloat {
        sizeClass == .regular ? 1.8 : 1
    }

    private func status(at now: Date) -> LocalizedStringKey {
        switch model.session?.state {
        case nil, .ended: "Ready to practice"
        case _ where model.isPausedAtLastNote(at: now): "Paused at your last note"
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

/// Views side by side in equal widths that fill the row. Its ideal width gives each the widest one's, unlike
/// `HStack`, whose ideal width is the sum, so `ViewThatFits` passes over it when a name would have to break to fit
/// its share. Compare `MyEqualWidthHStack` in Apple's "Composing custom layouts with SwiftUI", which gives each the
/// widest ideal width; this one fills the width it's given.
private struct EqualWidthRow: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let count = CGFloat(subviews.count)
        let widest = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let width = proposal.width ?? widest * count + spacing * (count - 1)
        let share = ProposedViewSize(width: (width - spacing * (count - 1)) / count, height: proposal.height)
        return CGSize(width: width, height: subviews.map { $0.sizeThatFits(share).height }.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let share = (bounds.width - spacing * CGFloat(subviews.count - 1)) / CGFloat(subviews.count)
        for (index, subview) in subviews.enumerated() {
            let x = bounds.minX + CGFloat(index) * (share + spacing)
            subview.place(
                at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                proposal: ProposedViewSize(width: share, height: bounds.height))
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

/// Second ticks while a session is counting, and only its first entry otherwise: a running session keeps
/// `.periodic`'s entries exactly, while an idle or paused Practice screen has nothing new to draw (NFR-10).
private struct PracticeTimelineSchedule: TimelineSchedule {
    let isCounting: Bool

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> AnySequence<Date> {
        guard isCounting else { return AnySequence([startDate]) }
        return AnySequence(PeriodicTimelineSchedule(from: startDate, by: 1).entries(from: startDate, mode: mode))
    }
}

#Preview("Ready") {
    let model = PracticeModel.preview(.ready)
    PracticeView(model: model, tags: .preview(for: model)) { _ in }
}

#Preview("Free piano sessions left") {
    let model = PracticeModel.preview(freeUsed: 4)
    PracticeView(model: model, tags: .preview(for: model)) { _ in }
}

#Preview("Free ones used, dark, AX5") {
    let model = PracticeModel.preview(freeUsed: 5)
    PracticeView(model: model, tags: .preview(for: model)) { _ in }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
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

#Preview("Not saved, a piano's session") {
    let model = PracticeModel.preview(.tooShort)
    PracticeView(model: model, tags: .preview(for: model)) { _ in }
}

#Preview("Not saved, a piano's session, dark, AX5") {
    let model = PracticeModel.preview(.tooShort)
    PracticeView(model: model, tags: .preview(for: model)) { _ in }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}

#Preview("Paused at your last note") {
    let model = PracticeModel.preview(.midiPaused)
    PracticeView(model: model, tags: .preview(for: model)) { _ in }
}

#Preview("Paused at your last note, dark, AX5") {
    let model = PracticeModel.preview(.midiPaused)
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

#Preview("Low battery") {
    let model = PracticeModel.preview(.lowBattery)
    PracticeView(model: model, tags: .preview(for: model)) { _ in }
}

#Preview("Low battery, dark, AX5") {
    let model = PracticeModel.preview(.lowBattery)
    PracticeView(model: model, tags: .preview(for: model)) { _ in }
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
