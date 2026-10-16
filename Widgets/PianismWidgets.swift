import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct PianismWidgets: WidgetBundle {
    var body: some Widget {
        StartWidget()
        PracticeLiveActivity()
    }
}

/// A small widget with one button that starts practice (spike #17).
struct StartWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "StartPractice", provider: StartProvider()) { _ in
            Button(intent: StartPracticeIntent()) {
                Label("Start", systemImage: "play.fill")
                    .font(.title2.bold())
            }
            .accessibilityIdentifier("widget.start")
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Start practice")
        .description("Starts a practice session.")
        .supportedFamilies([.systemSmall])
    }
}

struct StartEntry: TimelineEntry {
    let date: Date
}

struct StartProvider: TimelineProvider {
    func placeholder(in context: Context) -> StartEntry { StartEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (StartEntry) -> Void) {
        completion(StartEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StartEntry>) -> Void) {
        completion(Timeline(entries: [StartEntry(date: .now)], policy: .never))
    }
}

/// The running session on the Lock Screen and in the Dynamic Island (spike #17).
struct PracticeLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PracticeAttributes.self) { context in
            HStack {
                Label("Practicing", systemImage: "pianokeys")
                Spacer()
                elapsed(since: context.state.startedAt)
            }
            .font(.title3)
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Practicing", systemImage: "pianokeys")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    elapsed(since: context.state.startedAt)
                }
            } compactLeading: {
                Image(systemName: "pianokeys")
            } compactTrailing: {
                elapsed(since: context.state.startedAt).frame(maxWidth: 56)
            } minimal: {
                Image(systemName: "pianokeys")
            }
        }
    }

    private func elapsed(since start: Date) -> some View {
        Text(timerInterval: start...Date.distantFuture, countsDown: false).monospacedDigit()
    }
}
