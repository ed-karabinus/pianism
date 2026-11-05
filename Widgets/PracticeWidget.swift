import PianismCore
import PianismGlance
import PianismPersistence
import SwiftUI
import WidgetKit

/// The small Home Screen widget: today's practice, and Start (GLN-2).
struct PracticeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.practice, provider: PracticeProvider()) { entry in
            PracticeWidgetView(entry: entry)
        }
        .configurationDisplayName("Practice")
        .description("Today's practice time, and a button to start.")
        .supportedFamilies([.systemSmall])
    }
}

struct PracticeEntry: TimelineEntry {
    let date: Date
    /// Today's finished practice as of `date`.
    let finished: TimeInterval
    /// The running or paused session, which the widget counts on top of `finished` itself.
    let session: PracticeSession?
    /// The practice time at which the session ends itself, if the app has said (SES-4).
    var cap: TimeInterval?
    /// The session's practice before `date`'s day, which today's total leaves out: a session carried past
    /// midnight counts only from midnight on.
    var beforeToday: TimeInterval = 0
}

/// Reads the two App Group files the app writes: the running session (ADR 0003) and the day's finished practice
/// (ADR 0010). The extension's composition root, so the system clock is read here, and the rule is the core's (E3).
struct PracticeProvider: TimelineProvider {
    func placeholder(in context: Context) -> PracticeEntry {
        PracticeEntry(date: .now, finished: 25 * 60, session: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (PracticeEntry) -> Void) {
        completion(entry(at: .now))
    }

    /// Now, and the next local midnight, when the total starts over at 0 with no process running. A running
    /// session's clock counts by itself, and the app reloads the widget when the session changes.
    func getTimeline(in context: Context, completion: @escaping (Timeline<PracticeEntry>) -> Void) {
        let now = Date.now
        let calendar = Calendar.autoupdatingCurrent
        var entries = [entry(at: now)]
        if let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) {
            entries.append(entry(at: midnight))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date) -> PracticeEntry {
        let calendar = Calendar.autoupdatingCurrent
        let stored = try? FileRunningSessionStore(appGroup: AppGroup.identifier)?.current()
        let totals = FilePracticeTotals(appGroup: AppGroup.identifier)?.read()
        // An ended session still stored, as when neither history nor the outbox could take it, isn't being practiced.
        let session = stored?.state == .ended ? nil : stored
        return PracticeEntry(
            date: date, finished: totals?.today(at: date, in: calendar) ?? 0, session: session,
            cap: totals?.cap, beforeToday: session?.practiced(before: calendar.startOfDay(for: date)) ?? 0)
    }
}

struct PracticeWidgetView: View {
    let entry: PracticeEntry

    var body: some View {
        VStack(alignment: .leading) {
            Label(title, systemImage: "pianokeys")
                .font(.headline)
            Spacer()
            HStack(alignment: .lastTextBaseline) {
                time
                    .font(.title.bold())
                    .minimumScaleFactor(0.5)
                if entry.session == nil {
                    Spacer()
                    Button(intent: StartPracticeIntent()) {
                        Label("Start", systemImage: "play.fill")
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.circle)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var title: LocalizedStringKey {
        switch entry.session?.state {
        case nil, .ended: "Today"
        case .running: entry.session?.countsOnlyInApp == true ? "Paused" : "Practicing"
        case .paused: "Paused"
        }
    }

    /// Today's finished practice in whole minutes, rounded down as the app's clock is, so the widget never shows
    /// more than was practiced; or, with a session, today's total counting by itself from where the session's
    /// practice started, stopped at the pause while it's paused and at the cap, where the session ends itself, so
    /// no process needs to run (#164). A MIDI session stops at its last note, as only the open app hears the piano.
    @ViewBuilder private var time: some View {
        if let session = entry.session {
            let clock = session.practiceClock(cap: entry.cap)
            // Leaving out practice before today moves where the clock starts, not where it stops at the cap;
            // clamped, as a session already past the cap before today would start it past its end.
            let startsAt = min(clock.lowerBound - entry.finished + entry.beforeToday, clock.upperBound)
            Text(
                timerInterval: startsAt...clock.upperBound,
                pauseTime: session.pausedAwayAt, countsDown: false)
        } else {
            let duration = Duration.seconds(Int(entry.finished / 60) * 60)
            Text(duration.formatted(.units(allowed: [.hours, .minutes], width: .narrow)))
                .accessibilityLabel(duration.formatted(.units(allowed: [.hours, .minutes], width: .wide)))
        }
    }
}

/// A session started 95 minutes ago and paused 70 minutes ago: still paused at 25 minutes, or resumed 60 minutes ago,
/// so 85 minutes practiced and counting. On the real clock, as a live total counts from it. The Live Activity's
/// previews show the same session.
func previewSession(paused: Bool) -> PracticeSession {
    var session = PracticeSession(startedAt: .now - 95 * 60)
    try? session.pause(at: .now - 70 * 60)
    if !paused { try? session.resume(at: .now - 60 * 60) }
    return session
}

/// A preview piano session, played for 18 minutes until the app left 2 minutes ago.
func previewPianoSession() -> PracticeSession {
    var session = PracticeSession(startedAt: .now - 20 * 60, source: .midi)
    try? session.noteLastPlayed(at: .now - 2 * 60)
    return session
}

#Preview("Nothing yet", as: .systemSmall) {
    PracticeWidget()
} timeline: {
    PracticeEntry(date: .now, finished: 0, session: nil)
}

#Preview("25 minutes", as: .systemSmall) {
    PracticeWidget()
} timeline: {
    PracticeEntry(date: .now, finished: 25 * 60, session: nil)
}

#Preview("Practicing: 95 minutes in, 85 practiced, 20 minutes done before", as: .systemSmall) {
    PracticeWidget()
} timeline: {
    PracticeEntry(date: .now, finished: 20 * 60, session: previewSession(paused: false))
}

#Preview("Paused at 25 minutes", as: .systemSmall) {
    PracticeWidget()
} timeline: {
    PracticeEntry(date: .now, finished: 0, session: previewSession(paused: true))
}

#Preview("A piano session, stopped at its last note while the app is away", as: .systemSmall) {
    PracticeWidget()
} timeline: {
    PracticeEntry(date: .now, finished: 0, session: previewPianoSession())
}

// As just past midnight, 16 of its 18 minutes fell yesterday: today counts only from midnight.
#Preview("A piano session carried past midnight", as: .systemSmall) {
    PracticeWidget()
} timeline: {
    PracticeEntry(date: .now, finished: 0, session: previewPianoSession(), beforeToday: 16 * 60)
}

// The widget previews above take no modifiers, so dark and AX5 preview the view in a small widget's frame.
#Preview("2 hours 5 minutes, dark, AX5") {
    PracticeWidgetView(entry: PracticeEntry(date: .now, finished: 2 * 60 * 60 + 5 * 60, session: nil))
        .frame(width: 158, height: 158)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}

#Preview("Practicing, dark, AX5") {
    PracticeWidgetView(entry: PracticeEntry(date: .now, finished: 0, session: previewSession(paused: false)))
        .frame(width: 158, height: 158)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}

#Preview("Paused, dark, AX5") {
    PracticeWidgetView(entry: PracticeEntry(date: .now, finished: 0, session: previewSession(paused: true)))
        .frame(width: 158, height: 158)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
