import ActivityKit
import PianismGlance
import SwiftUI
import WidgetKit

/// The running session on the Lock Screen and in the Dynamic Island, with Pause or Resume, and Stop (GLN-1). The app
/// starts, updates and ends it (ADR 0010); the clock counts by itself, and stops at the cap or the pause.
struct PracticeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PracticeAttributes.self) { context in
            PracticeActivityView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    PracticeTitle(state: context.state)
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PracticeClock(state: context.state)
                        .font(.title2)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    PracticeButtons(state: context.state)
                }
            } compactLeading: {
                Image(systemName: "pianokeys")
            } compactTrailing: {
                // A timer text reserves the width of its widest value and leads in it, which sat the spike's
                // off-centre; a fixed width wide enough for "4:00:00" and a trailing alignment pin it.
                PracticeClock(state: context.state)
                    .font(.caption)
                    .frame(width: 56, alignment: .trailing)
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

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                PracticeTitle(state: state)
                    .font(.headline)
                Spacer()
                PracticeClock(state: state)
                    .font(.title2)
            }
            PracticeButtons(state: state)
        }
        .padding()
    }
}

private struct PracticeTitle: View {
    let state: PracticeAttributes.ContentState

    var body: some View {
        Label(state.pausedAt == nil ? "Practicing" : "Paused", systemImage: "pianokeys")
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

/// Pause or Resume, by the state, and Stop. Each runs in the app's process (ADR 0010).
private struct PracticeButtons: View {
    let state: PracticeAttributes.ContentState

    var body: some View {
        HStack {
            if state.pausedAt == nil {
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
    PracticeAttributes.ContentState(session: previewSession(paused: paused), cappedAt: 4 * 60 * 60)
}

private let previewAttributes = PracticeAttributes(sessionID: UUID())

#Preview("Lock Screen", as: .content, using: previewAttributes) {
    PracticeLiveActivity()
} contentStates: {
    previewState(paused: false)
    previewState(paused: true)
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
}

#Preview("Island, minimal", as: .dynamicIsland(.minimal), using: previewAttributes) {
    PracticeLiveActivity()
} contentStates: {
    previewState(paused: false)
}

// The activity previews above take no modifiers, so dark and AX5 preview the Lock Screen view on its own.
#Preview("Lock Screen, dark, AX5") {
    PracticeActivityView(state: previewState(paused: false))
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}

#Preview("Lock Screen, paused, dark, AX5") {
    PracticeActivityView(state: previewState(paused: true))
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
