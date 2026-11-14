import ActivityKit
import PianismGlance
import SwiftUI
import WidgetKit

/// The running session on the Lock Screen and in the Dynamic Island, with Pause or Resume, and Stop (GLN-1). The app
/// starts, updates and ends it (ADR 0010); the clock counts by itself, and stops at the cap or the pause. A MIDI
/// session shows paused at its last note, as only the open app hears the piano, and once the session would have ended
/// itself, the activity is stale and says it ended.
struct PracticeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PracticeAttributes.self) { context in
            PracticeActivityView(state: context.state, isStale: context.isStale)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PracticeTitle(state: context.state, isStale: context.isStale)
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PracticeClock(state: context.state)
                        .font(.title2)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack {
                        PracticeNote(state: context.state, isStale: context.isStale)
                        PracticeButtons(state: context.state, isStale: context.isStale)
                    }
                }
            } compactLeading: {
                Image(systemName: "pianokeys")
            } compactTrailing: {
                // A timer text reserves the width of its widest value and leads in it, which sat the spike's
                // off-centre; a width just wide enough for "4:00:00" (drawn 47 points wide, iOS 27.2) and a trailing
                // alignment pin it. With another app's activity beside it, the island cut a 56-point width off at
                // "1:00:0" (device check 2026-11-13), so the width is no wider than the text, and the clock can
                // shrink if the island offers less.
                PracticeClock(state: context.state)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(minWidth: 0, idealWidth: 50, maxWidth: 50, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
            } minimal: {
                Image(systemName: "pianokeys")
            }
        }
    }
}

/// The Lock Screen and banner.
struct PracticeActivityView: View {
    let state: PracticeAttributes.ContentState
    let isStale: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                PracticeTitle(state: state, isStale: isStale)
                    .font(.headline)
                Spacer()
                PracticeClock(state: state)
                    .font(.title2)
            }
            PracticeNote(state: state, isStale: isStale)
            PracticeButtons(state: state, isStale: isStale)
        }
        .padding()
    }
}

private struct PracticeTitle: View {
    let state: PracticeAttributes.ContentState
    let isStale: Bool

    var body: some View {
        Label(title, systemImage: "pianokeys")
    }

    private var title: LocalizedStringKey {
        if isStale { "Ended" } else if state.pausedAt == nil { "Practicing" } else { "Paused" }
    }
}

/// Why the clock stopped when only the app can say more: a MIDI session waiting for the app to hear the piano, or
/// a session that has ended itself since (decided with Ed, 2026-11-03).
private struct PracticeNote: View {
    let state: PracticeAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if isStale {
            Text("Open Pianism to see it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if state.countsOnlyInApp {
            Text("Open Pianism to keep counting.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// The practice time, counting while the session runs and stopped at the pause or the cap, with no process running.
private struct PracticeClock: View {
    let state: PracticeAttributes.ContentState

    var body: some View {
        Text(timerInterval: state.timer, pauseTime: state.pausedAt, countsDown: false)
            .monospacedDigit()
    }
}

/// Pause or Resume, by the state, and Stop. Each runs in the app's process (ADR 0010). A MIDI session waiting for
/// the app offers Stop only, as playing resumes it, and an ended one offers nothing.
private struct PracticeButtons: View {
    let state: PracticeAttributes.ContentState
    let isStale: Bool

    var body: some View {
        if !isStale {
            buttons
        }
    }

    private var buttons: some View {
        HStack {
            if state.countsOnlyInApp {
                // Playing resumes it, in the app, so there's no Pause or Resume.
            } else if state.pausedAt == nil {
                Button(intent: PausePracticeIntent()) {
                    Label("Pause", systemImage: "pause.fill")
                }
            } else {
                Button(intent: ResumePracticeIntent()) {
                    Label("Resume", systemImage: "play.fill")
                }
            }
            Button(intent: StopPracticeIntent()) {
                Label("Stop", systemImage: "stop.fill")
            }
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity)
    }
}

/// The widget's preview session, 85 minutes practiced and counting, or paused at 25 minutes, as the activity shows it
/// with the app's 4-hour cap.
private func previewState(paused: Bool) -> PracticeAttributes.ContentState {
    PracticeAttributes.ContentState(session: previewSession(paused: paused), cappedAt: 4 * 60 * 60, appOnScreen: false)
}

private let previewAttributes = PracticeAttributes(sessionID: UUID())

private let previewPianoState = PracticeAttributes.ContentState(
    session: previewPianoSession(), cappedAt: nil, appOnScreen: false)

#Preview("Lock Screen", as: .content, using: previewAttributes) {
    PracticeLiveActivity()
} contentStates: {
    previewState(paused: false)
    previewState(paused: true)
    previewPianoState
}

#Preview("Island, compact", as: .dynamicIsland(.compact), using: previewAttributes) {
    PracticeLiveActivity()
} contentStates: {
    previewState(paused: false)
    previewState(paused: true)
}

#Preview("Island, expanded", as: .dynamicIsland(.expanded), using: previewAttributes) {
    PracticeLiveActivity()
} contentStates: {
    previewState(paused: false)
    previewState(paused: true)
    previewPianoState
}

#Preview("Island, minimal", as: .dynamicIsland(.minimal), using: previewAttributes) {
    PracticeLiveActivity()
} contentStates: {
    previewState(paused: false)
}

// The activity previews above take no modifiers, so dark and AX5 preview the Lock Screen view on its own.
#Preview("Lock Screen, dark, AX5") {
    PracticeActivityView(state: previewState(paused: false), isStale: false)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}

#Preview("Lock Screen, paused, dark, AX5") {
    PracticeActivityView(state: previewState(paused: true), isStale: false)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}

#Preview("Lock Screen, a piano session away, dark, AX5") {
    PracticeActivityView(state: previewPianoState, isStale: false)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}

// Stale shows only on a device or in the activity's own timeline, so it's previewed on the view.
#Preview("Lock Screen, ended") {
    PracticeActivityView(state: previewPianoState, isStale: true)
}
