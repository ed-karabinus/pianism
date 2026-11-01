import PianismCore
import PianismGlance
import PianismPersistence
import Synchronization
import WidgetKit
import os

/// Shows practice outside the app (ADR 0010): writes today's finished practice to the App Group and has the widget
/// read it, and the stored session, again. Lives in the app, not a package: WidgetKit isn't on macOS, so
/// `make test-adapters` couldn't run it.
final class SystemPracticeGlance: PracticeGlance {
    private let file: FilePracticeTotals
    private let lastWritten = Mutex<PracticeTotals?>(nil)
    private let lastShown = Mutex<PracticeSession?>(nil)
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

    func show(_ session: PracticeSession?) {
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
}
