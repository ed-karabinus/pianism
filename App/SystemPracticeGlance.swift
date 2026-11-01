import ActivityKit
import PianismCore
import PianismGlance
import PianismPersistence
import Synchronization
import WidgetKit
import os

/// Shows practice outside the app (ADR 0010): writes today's finished practice to the App Group and has the widget
/// read it, and the stored session, again; and shows the session as a Live Activity, started, updated and ended from
/// here only. Lives in the app, not a package: WidgetKit and ActivityKit aren't on macOS, so `make test-adapters`
/// couldn't run it.
final class SystemPracticeGlance: PracticeGlance {
    private let file: FilePracticeTotals
    private let lastWritten = Mutex<PracticeTotals?>(nil)
    private let lastShown = Mutex<PracticeSession?>(nil)
    /// The last change sent to ActivityKit. Each waits for the one before, so a pause can't land after the resume
    /// that followed it.
    private let pending = Mutex<Task<Void, Never>?>(nil)
    private let logger = Logger(subsystem: "com.edkarabinus.Pianism", category: "glance")

    init(file: FilePracticeTotals) {
        self.file = file
    }

    func show(_ totals: PracticeTotals) {
        // History refreshes on every return to the foreground, and most of those change nothing; the widget's
        // reload budget is spent only when the total did.
        guard lastWritten.withLock({ $0 != totals }) else { return }
        do {
            try file.write(totals)
        } catch {
            logger.error("Couldn't write the practice totals for the widget: \(error, privacy: .public)")
            return
        }
        lastWritten.withLock { $0 = totals }
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.practice)
    }

    func show(_ session: PracticeSession?, cappedAt cap: TimeInterval?) {
        // An ended session still stored, as when neither history nor the outbox could take it, isn't being practiced.
        let session = session?.state == .ended ? nil : session
        pending.withLock { previous in
            previous = Task { [previous] in
                await previous?.value
                await self.reconcileActivities(with: session, cappedAt: cap)
            }
        }
        // Practice refreshes at every tick and tag change too; the widget reads the session's file itself, so it
        // only needs a reload when what it draws from changed: a new session, or one paused, resumed or gone.
        let changed = lastShown.withLock { last in
            guard last?.id != session?.id || last?.state != session?.state else { return false }
            last = session
            return true
        }
        guard changed else { return }
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetKind.practice)
    }

    /// Waits until ActivityKit has taken every change shown so far. An intent run in the background calls this
    /// before it returns, as the system may suspend the app once it has.
    func settle() async {
        await pending.withLock { $0 }?.value
    }

    /// Brings the system's activities in line with the stored session: the session's live activity is updated when
    /// what it shows changed, any other, such as one that outlived a killed app, is ended, and a session with none
    /// gets one. Starting one can fail, as when Live Activities are off in Settings, and that never fails the session.
    /// Nothing automated reaches this (ADR 0010); the device checklist's L rows do.
    private func reconcileActivities(with session: PracticeSession?, cappedAt cap: TimeInterval?) async {
        let content = session.map {
            ActivityContent(state: PracticeAttributes.ContentState(session: $0, cappedAt: cap), staleDate: nil)
        }
        var shown = false
        for activity in Activity<PracticeAttributes>.activities {
            // An activity the system ended, as after 8 hours with a session paused overnight, stays listed as ended
            // for up to 4 hours more, and updating it does nothing, so only a live one counts as showing the
            // session, and only the first, so a duplicate is ended rather than kept.
            let live = [.active, .stale].contains(activity.activityState)
            if let session, let content, activity.attributes.sessionID == session.id, live, !shown {
                shown = true
                if activity.content.state != content.state {
                    await activity.update(content)
                }
            } else {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
        }
        guard let session, let content, !shown else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            logger.info("Live Activities are off, so the session shows in the app and the widget only")
            return
        }
        do {
            _ = try Activity.request(attributes: PracticeAttributes(sessionID: session.id), content: content)
        } catch {
            logger.info("Couldn't start the Live Activity: \(error, privacy: .public)")
        }
    }
}
