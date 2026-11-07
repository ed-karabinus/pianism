import Accessibility
import Foundation
import Observation
import PianismCore
import os

/// State and commands for the Practice screen (SES-1 to SES-4, SES-6).
///
/// Every command goes through a ``SessionRecorder``, which stores it before returning, so the
/// screen always shows what is stored, even if the app was killed or another process changed it.
@MainActor
@Observable
public final class PracticeModel: TagTarget {
    /// The running or paused session, or `nil` when ready to start. Also an ended session that neither
    /// history nor the outbox could take, which shows as ready to start.
    private(set) var session: PracticeSession?
    /// Whether the welcome is showing (ONB-1). A session starting closes it, even from a piano's notes.
    var isShowingWelcome = false
    /// The session that just ended and was kept, shown until the next one starts.
    private(set) var lastSession: PracticeSession?
    /// How many finished sessions are waiting to move into history, which couldn't save them yet.
    private(set) var waitingCount = 0
    /// Whether to show that a change couldn't be stored.
    var isShowingStorageError = false
    /// Whether the running session has practiced past the nudge, so Practice asks "Still practicing?" (SES-3).
    private(set) var isPastNudge = false  // mutate:ignore - init's refresh() sets it
    /// The session whose "Still practicing?" was answered, in the app or its notification, so it's asked once per
    /// session (SES-3). Stored per device.
    private(set) var answeredID: UUID?
    /// What the system allows, once read, as it can change in its Settings app while the app is away (SET-1).
    private(set) var notificationPermission: NotificationPermission?
    /// Whether the banner offers the notification, until the system has asked, as it asks once. Not with the switch off
    /// in Settings, which already said no (SES-3, SET-1).
    var canAskForNudges: Bool { notifiesStillPracticing && notificationPermission == .notAsked }
    /// The setting, kept apart from what the system allows, so allowing it in the Settings app turns it back on.
    private var notifiesStillPracticing: Bool {
        didSet {
            defaults.set(notifiesStillPracticing, forKey: SettingsKey.notifiesStillPracticing)
            refresh()
        }
    }
    /// The switch in Settings: on only while the system allows notifications too. Turning it on asks the system, if it
    /// hasn't asked yet (SET-1).
    var notifiesWhenAway: Bool {
        get { notifiesStillPracticing && notificationPermission == .allowed }
        set {
            notifiesStillPracticing = newValue
            if newValue { Task { await askForNudges() } }
        }
    }
    /// Whether the daily reminder is wanted, kept apart from what the system allows, as the setting above is.
    private var wantsDailyReminder: Bool {
        didSet {
            defaults.set(wantsDailyReminder, forKey: SettingsKey.remindsDaily)
            planReminders()
        }
    }
    /// The daily reminder's time, in minutes after local midnight.
    private var dailyReminderMinute: Int {
        didSet {
            defaults.set(dailyReminderMinute, forKey: SettingsKey.dailyReminderMinute)
            planReminders()
        }
    }
    /// The switch in Settings, which reads and asks as `notifiesWhenAway` does (SET-1).
    var remindsDaily: Bool {
        get { wantsDailyReminder && notificationPermission == .allowed }
        set {
            wantsDailyReminder = newValue
            if newValue { Task { await askForNudges() } }
        }
    }
    /// The daily reminder's time, as today's date at that time, for the picker in Settings.
    var dailyReminderTime: Date {
        get {
            calendar.date(
                bySettingHour: dailyReminderMinute / 60, minute: dailyReminderMinute % 60, second: 0, of: clock.now)
                ?? clock.now
        }
        set {
            let time = calendar.dateComponents([.hour, .minute], from: newValue)
            dailyReminderMinute = (time.hour ?? 0) * 60 + (time.minute ?? 0)
        }
    }
    /// What the notification opened Practice to show, until it's shown: the question, or the end being picked.
    var nudgeOpened: NudgeOpening?
    /// The session that ended itself at the cap, until the banner explaining it is acted on (SES-4).
    private var cappedID: UUID?
    /// Whether the last MIDI session had under a minute of played time, so it wasn't saved, until the next start
    /// (MIDI-1).
    private(set) var lastRunWasTooShort = false
    /// The names of the pianos connected, as the system gives them (MIDI-2).
    public var connectedPianos: [String] = [] {
        didSet { readyUntil = clock.now + Self.readyAwake }
    }
    /// Until when Practice keeps the screen on with a piano connected, ready for a note: 15 minutes after the last
    /// note, the piano connecting or the app coming to the front, which is about when a piano switches itself off
    /// (MIDI-R5, decided with Ed, 2026-10-28). It matters only with a piano connected, and not during a MIDI session,
    /// which keeps the screen on anyway, so it moves on at the session's end.
    private(set) var readyUntil: Date?
    private static let readyAwake: TimeInterval = 15 * 60
    /// Turns the piano's notes into MIDI sessions, following the stored session at each refresh (MIDI-1).
    @ObservationIgnored private var detector: MIDIDetector

    let clock: any WallClock
    /// The practice time after which Practice asks "Still practicing?" (SES-3). Set in Settings, where a change
    /// applies to the running session at once (SET-1).
    var nudge: TimeInterval {
        didSet {
            defaults.set(nudge, forKey: SettingsKey.stillPracticingAfter)
            refresh()
        }
    }
    /// The practice time that ends a running session by itself, in case it was left running (SES-4). Set in
    /// Settings, but not while a timer session runs (SET-1).
    var cap: TimeInterval {
        didSet {
            defaults.set(cap, forKey: SettingsKey.automaticCapAfter)
            refresh()
        }
    }
    /// How many notes within 10 s start a MIDI session (MIDI-1). Set in Settings (SET-1).
    var startNotes: Int {
        didSet {
            defaults.set(startNotes, forKey: SettingsKey.midiStartNotes)
            detector.settings.startNotes = startNotes
        }
    }
    /// The silence after which a MIDI session pauses (MIDI-1). Set in Settings, where a change applies to the session
    /// being played at once (SET-1).
    var pauseAfter: TimeInterval {
        didSet {
            defaults.set(pauseAfter, forKey: SettingsKey.midiPauseAfter)
            detector.settings.pauseAfter = pauseAfter
            tick()
        }
    }
    /// The silence after which a MIDI session ends and is saved (MIDI-1). Set in Settings, as `pauseAfter` is.
    var saveAfter: TimeInterval {
        didSet {
            defaults.set(saveAfter, forKey: SettingsKey.midiSaveAfter)
            detector.settings.saveAfter = saveAfter
            tick()
        }
    }
    private let recorder: SessionRecorder
    private let history: any SessionHistory
    private let outbox: any SessionOutbox
    private let nudges: any PracticeNudges
    private let glance: any PracticeGlance
    private let defaults: UserDefaults
    private let calendar = Calendar.autoupdatingCurrent
    /// Says a line to VoiceOver, whose user can't see the time drop back. A seam, so the model's tests hear it.
    private let announce: @MainActor (String) -> Void
    private let logger = Logger(subsystem: "com.edkarabinus.Pianism", category: "practice")
    /// The key under which the banner's `@AppStorage` kept the answer, so answers given before stay given.
    private static let answeredKey = "stillPracticingAnswered"

    public init(
        store: any RunningSessionStore, history: any SessionHistory, outbox: any SessionOutbox, clock: any WallClock,
        nudges: any PracticeNudges, glance: any PracticeGlance, defaults: UserDefaults, nudge: TimeInterval,
        cap: TimeInterval, midi: MIDISettings = .init(),
        announce: @escaping @MainActor (String) -> Void = PracticeModel.tellVoiceOver
    ) {
        self.recorder = SessionRecorder(store: store, clock: clock, midi: midi)
        self.detector = MIDIDetector(midi)
        self.history = history
        self.outbox = outbox
        self.clock = clock
        self.nudges = nudges
        self.glance = glance
        self.defaults = defaults
        self.announce = announce
        self.nudge = nudge
        self.cap = cap
        startNotes = midi.startNotes
        pauseAfter = midi.pauseAfter
        saveAfter = midi.saveAfter
        answeredID = defaults.string(forKey: Self.answeredKey).flatMap(UUID.init(uuidString:))
        notifiesStillPracticing = defaults.object(forKey: SettingsKey.notifiesStillPracticing) as? Bool ?? true
        wantsDailyReminder = defaults.bool(forKey: SettingsKey.remindsDaily)
        dailyReminderMinute =
            defaults.object(forKey: SettingsKey.dailyReminderMinute) as? Int ?? DailyReminder.defaultMinute
        // Loads the stored session now, so the first frame after a relaunch already shows it, with the silence
        // since its last change applied. As `cameToFront()`, but not yet on screen: a Live Activity's button can
        // launch the app in the background.
        readyUntil = clock.now + Self.readyAwake
        tick()
    }

    /// Opens the welcome on the first launch that finds no practice at all. It's decided once, so someone who already
    /// practiced never sees it, even after deleting every session, but not while storage can't say (ONB-1).
    func offerWelcome(historyIsEmpty: Bool?) {
        guard let historyIsEmpty, !isShowingStorageError, !defaults.bool(forKey: SettingsKey.hasDecidedWelcome) else {
            return
        }
        defaults.set(true, forKey: SettingsKey.hasDecidedWelcome)
        isShowingWelcome = historyIsEmpty && session == nil
    }

    /// Starts a session (SES-1). Public for the widget's Start, which the app runs through this model (ADR 0010).
    public func start() {
        perform {
            try recorder.start()
            lastSession = nil
            lastRunWasTooShort = false
        }
    }

    /// Counts a note played on a connected piano (MIDI-1). Three within 10 s, or as many as set, start a MIDI
    /// session. On a session started by tapping, notes only show the user is there, so past the nudge they answer
    /// "Still practicing?" as a Pause does (MIDI-R4, SES-3).
    public func noteOn(at date: Date) {
        if session?.source != .midi {  // mutate:ignore - in a session it'd only refresh at each note; its end sets it
            readyUntil = max(readyUntil ?? .distantPast, date + Self.readyAwake)
        }
        guard session?.source != .timer else {
            answerIfPastNudge()
            return
        }
        let effects = detector.handle(.noteOn(date))
        apply(effects)
        if case .start = effects.first {
            // NFR-5 allows 250 ms from the note that starts a session; a device run reads this line.
            let latency = clock.now.timeIntervalSince(date) * 1000
            logger.info(
                "MIDI session started \(latency, format: .fixed(precision: 0)) ms after the note that set it off")
        }
    }

    /// Pauses the session (SES-2). Public for the Live Activity's Pause, which the app runs through this model
    /// (ADR 0010).
    public func pause() {
        answerIfPastNudge()
        perform { try recorder.pause() }
    }

    /// Resumes the session (SES-2). Public for the Live Activity's Resume, as `pause()` is.
    public func resume() {
        answerIfPastNudge()
        perform { try recorder.resume() }
    }

    /// Whether Practice asks "Still practicing?" (SES-3).
    var isAskingStillPracticing: Bool { isPastNudge && session.map { $0.id != answeredID } == true }

    /// Answers "Still practicing?" for the session with this ID, from the banner or the notification (SES-3).
    public func answerStillPracticing(for id: UUID) {
        answeredID = id
        defaults.set(id.uuidString, forKey: Self.answeredKey)
    }

    /// A Pause or Resume once practice has passed the nudge shows the user is there, so it answers "Still
    /// practicing?" for the session (SES-3).
    private func answerIfPastNudge() {
        if let session, answeredID != session.id, session.elapsed(at: clock.now) >= nudge {
            answerStillPracticing(for: session.id)
        }
    }

    /// Shows Practice with the question about the session with this ID or, after the notification's "I stopped
    /// earlier", with its end being picked (SES-3).
    public func open(fromNudgeAbout id: UUID, pickingEnd: Bool) {
        nudgeOpened = NudgeOpening(sessionID: id, pickingEnd: pickingEnd)
    }

    /// Shows Practice after a tap on the daily reminder, whichever tab was open (SET-1).
    public func openFromReminder() {
        nudgeOpened = NudgeOpening(sessionID: nil, pickingEnd: false)
    }

    /// Reads what the system allows, and tops the reminders up, as they run out unless the app is opened (SET-1).
    /// Public for the widget's and the Live Activity's buttons, which change a session without opening the app.
    public func checkNudges() async {
        notificationPermission = await nudges.permission()
        planReminders()
    }

    private func planReminders() {
        // Not before the system has answered, as when a button launches the app in the background: the reminder would
        // read as off, and all of them would go. Turning it off needs no answer.
        if wantsDailyReminder && notificationPermission == nil { return }
        guard remindsDaily else { return nudges.cancelReminders() }
        nudges.scheduleReminders(
            at: DailyReminder.dates(
                atMinute: dailyReminderMinute, after: clock.now, skippingToday: hasPracticedToday, in: calendar))
    }

    /// Whether a session started today, or one is running, whenever it started. Not one paused on an earlier day, which
    /// nothing ends, as it would silence the reminder until it's stopped (decided with Ed, 2026-11-05). If history can't
    /// be read, today counts as not practiced, as a reminder too many costs less than a day missed.
    private var hasPracticedToday: Bool {
        guard session?.state != .running else { return true }
        let sessions =
            [session].compactMap { $0 } + ((try? history.sessions()) ?? []) + ((try? outbox.sessions()) ?? [])
        // A whole second, the least History lists on a day, so the two agree, however late it started.
        let today = calendar.startOfDay(for: clock.now)
        return sessions.contains { $0.practiced(from: today, before: clock.now) >= 1 }
    }

    /// Asks for the notification, if the system hasn't asked yet, and adds it for the session running, which the
    /// system refused until now (SES-3, SET-1).
    func askForNudges() async {
        await checkNudges()
        guard notificationPermission == .notAsked else { return }
        await nudges.requestPermission()
        await checkNudges()
        refresh()
    }

    /// Ends the session now, or a MIDI session at the earlier of now and 5 s after its last note (MIDI-R4). Public for
    /// the Live Activity's Stop, as `pause()` is.
    public func stop() {
        if session?.source == .midi {
            apply(detector.handle(.stop(clock.now)))
        } else {
            perform { try recorder.stop() }
        }
    }

    /// Shows the stored session, then pauses or ends a MIDI session whose silence has lasted long enough, as when
    /// the app comes back after half an hour (MIDI-R3). Call at launch, on becoming active and at `nextRefresh`.
    func tick() {
        refresh()
        apply(detector.handle(.tick(clock.now)))
        if let readyUntil, clock.now >= readyUntil { self.readyUntil = nil }
    }

    /// Ticks as the app comes to the front, at launch or back from elsewhere, which keeps the screen on a while longer
    /// with a piano connected (MIDI-R5).
    func cameToFront() {
        isOnScreen = true
        readyUntil = clock.now + Self.readyAwake
        tick()
        Task { await checkNudges() }
    }

    /// Stores the MIDI session's last note as the app leaves the screen, so if it's killed while away, the silence
    /// counts from that note, not from the last change (MIDI-1). Either way, the glance learns the app has gone, and
    /// today's reminder goes if today's practice is done (SET-1): sessions change while the app is open, and the
    /// system shows no reminder in front of it.
    func leaveForeground() {
        isOnScreen = false
        defer { planReminders() }
        // The detector has a last note only while a MIDI session is playing.
        guard let lastNote = detector.lastNote else { return refresh() }
        perform { try recorder.noteLastPlayed(at: lastNote) }
    }

    /// Whether the app is open on screen, hearing the piano, so a MIDI session's clock outside it counts on (GLN-1).
    /// Not until it comes to the front, as a Live Activity's button can launch it in the background.
    private var isOnScreen = false

    /// Says `line` over whatever VoiceOver is saying, which otherwise drops it, as when it's naming the app that opened.
    public static func tellVoiceOver(_ line: String) {
        var line = AttributedString(line)
        line.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(line).post()
    }

    /// Stores the detector's effects in one command, so a note refreshes once, and only if it changed something.
    /// A MIDI session ended with under a minute played is dropped in the refresh, which Practice then says.
    private func apply(_ effects: [MIDIDetector.Effect]) {
        guard !effects.isEmpty else { return }  // mutate:ignore - without it, a note only refreshes needlessly
        var endedID: UUID?
        perform {
            for effect in effects {
                switch effect {
                case .start(let date):
                    try recorder.start(at: date)
                    lastRunWasTooShort = false
                case .pause(let date):
                    try recorder.pause(at: date)
                case .resume(let date):
                    try recorder.resume(at: date)
                case .end(let lastNote, let date):
                    readyUntil = lastNote + Self.readyAwake
                    // A Stop dated before the last note, as after the clock steps back, ends the session at it.
                    endedID = try recorder.end(afterLastNote: lastNote, at: max(date, lastNote)).id
                }
            }
        }
        // Neither kept nor still stored, as one is when history and the outbox both fail, so it was dropped.
        if let endedID {
            lastRunWasTooShort = lastSession?.id != endedID && session?.id != endedID
        }
        // Last among the effects and stored, so not when a late note resumes it at once or the store refused the pause.
        if case .pause = effects.last, session?.state == .paused {
            let time = ElapsedTime.spoken(elapsed(at: clock.now))
            announce(String(localized: "Paused at your last note, \(time)", bundle: .module))
        }
    }

    /// Ends the session at `date`, when it ended before now (SES-3). A date before the last resume, as when the
    /// clock steps back, ends it at the resume.
    func stop(at date: Date) {
        let end = session.map { max(date, $0.latestEvent).keepingSeconds(of: $0.startedAt, within: stopRange(of: $0)) }
        perform { try recorder.stop(at: end ?? date) }
    }

    /// The times "I stopped earlier" offers, from the last resume to now (SES-3). The upper bound never falls
    /// below the lower, as a ClosedRange traps then, should the clock step back.
    func stopRange(of session: PracticeSession) -> ClosedRange<Date> {
        session.latestEvent...max(session.latestEvent, clock.now)
    }

    /// When a timer session reaches the nudge or the cap next, or a MIDI session's silence pauses or ends it, so
    /// Practice ticks then (SES-3, SES-4, MIDI-1).
    var nextRefresh: Date? {
        let now = clock.now
        return deadlines.filter { $0 > now }.min()
    }

    /// The earliest of those, passed or not, which the wake-up waits on: it moves only when a deadline does, as when
    /// Settings changes the nudge, and not as one passes, which would skip it (SET-1).
    var firstDeadline: Date? { deadlines.min() }

    private var deadlines: [Date] {
        // The silences are read here as well as by the detector, which isn't observed, so RootView's wake-up moves
        // when one changes in Settings. The refresh a change runs doesn't move it: an unchanged session notifies no
        // one (a planted bug without this line was caught).
        _ = (pauseAfter, saveAfter)
        return ([nudge, cap].map { timerSession?.whenPracticeReaches($0) } + [detector.nextDeadline]).compactMap { $0 }
    }

    /// The session, unless it's a MIDI session: the piano shows the user is there, and a silence ends it, so it
    /// isn't asked "Still practicing?" or capped (SES-3, SES-4).
    private var timerSession: PracticeSession? { session?.source == .midi ? nil : session }

    /// Whether the screen stays on: while a MIDI session lasts, pauses included, as a locked phone can't hear the
    /// note that resumes it, and while Practice shows with a piano connected, so it hears the first, until
    /// `readyUntil` (MIDI-R5).
    func keepsScreenAwake(showingPractice: Bool) -> Bool {
        session.map { $0.source == .midi && $0.state != .ended } == true
            || showingPractice && !connectedPianos.isEmpty && readyUntil != nil
    }

    /// The battery, read only while the screen is kept on.
    var battery: BatteryReading?

    /// Whether Practice warns that the battery is at 20 % or less while it keeps the screen on, unless plugged in
    /// (NFR-10). iOS reports the level as a Float in 5 % steps, so "below 20 %" would wait for 15 %, and its 20 % is
    /// a hair above 0.2: whole percents (decided with Ed, 2026-10-29).
    var showsLowBattery: Bool {
        keepsScreenAwake(showingPractice: true)
            && battery.map { ($0.level * 100).rounded() <= 20 && !$0.isPluggedIn } == true
    }

    /// Whether the session's shown time changes with each second, so Practice ticks only then (NFR-10):
    /// only while running, which for a piano session includes until its silence pause is due.
    var isCounting: Bool { session?.state == .running }

    /// The session's time at `now` as the next tick leaves it: a MIDI session's silence stops at its last note
    /// once it pauses it, and a timer session stops at the cap. So a frame drawn before that tick, as while the
    /// app comes back from the lock screen, shows no time that isn't counted (MIDI-1, SES-4).
    func elapsed(at now: Date) -> TimeInterval {
        let shownAt = min(now, detector.pauseDue(at: now) ?? now, timerSession?.whenPracticeReaches(cap) ?? now)
        return session?.elapsed(at: shownAt) ?? 0
    }

    /// Whether the session paused itself at its last note after a silence, rather than at a tap, or the next tick
    /// pauses it there (MIDI-1).
    func isPausedAtLastNote(at now: Date) -> Bool {
        session?.state == .paused && detector.isPausedBySilence || detector.pauseDue(at: now) != nil
    }

    /// Keeps the welcome from showing, for end-to-end tests that are about something else.
    public static func skipWelcome(in defaults: UserDefaults) {
        defaults.set(true, forKey: SettingsKey.hasDecidedWelcome)
    }

    /// The nudge set in Settings, or 90 minutes, for the app to launch with (SET-1, SES-3).
    public static func storedNudge(in defaults: UserDefaults) -> TimeInterval {
        stored(SettingsKey.stillPracticingAfter, in: defaults) ?? 90 * 60
    }

    /// The cap set in Settings, or 4 hours, for the app to launch with (SET-1, SES-4).
    public static func storedCap(in defaults: UserDefaults) -> TimeInterval {
        stored(SettingsKey.automaticCapAfter, in: defaults) ?? 4 * 60 * 60
    }

    /// How a MIDI session starts, pauses and is saved, as set in Settings, or the defaults (SET-1).
    public static func storedMIDI(in defaults: UserDefaults) -> MIDISettings {
        var midi = MIDISettings()
        midi.startNotes = defaults.object(forKey: SettingsKey.midiStartNotes) as? Int ?? midi.startNotes
        midi.pauseAfter = stored(SettingsKey.midiPauseAfter, in: defaults) ?? midi.pauseAfter
        midi.saveAfter = stored(SettingsKey.midiSaveAfter, in: defaults) ?? midi.saveAfter
        return midi
    }

    private static func stored(_ key: String, in defaults: UserDefaults) -> TimeInterval? {
        defaults.object(forKey: key) as? TimeInterval
    }

    /// The nudges Settings offers: every half hour up to 4 hours, below the cap, so Practice asks before it stops
    /// a session (SET-1, decided with Ed, 2026-11-02).
    var nudgeChoices: [TimeInterval] {
        Self.choices(stride(from: 30 * 60, through: 4 * 60 * 60, by: 30 * 60).filter { $0 < cap }, with: nudge)
    }

    /// The caps Settings offers: every hour from 1 to 8, above the nudge (SET-1, decided with Ed, 2026-11-02).
    var capChoices: [TimeInterval] {
        Self.choices(stride(from: 60 * 60, through: 8 * 60 * 60, by: 60 * 60).filter { $0 > nudge }, with: cap)
    }

    /// Whether Settings can change the cap: not while a timer session runs, which a new cap would end or stretch
    /// (SET-1, decided with Ed, 2026-11-02).
    var canChangeCap: Bool { timerSession == nil }

    /// The silences Settings offers to pause a MIDI session, from 15 s to 5 minutes, each shorter than the one that
    /// saves it (SET-1, decided with Ed, 2026-11-03).
    var pauseChoices: [TimeInterval] {
        Self.choices([15, 30, 45, 60, 120, 180, 300].filter { $0 < saveAfter }, with: pauseAfter)
    }

    /// The silences Settings offers to save a MIDI session, from 2 minutes to an hour, each longer than the pause.
    var saveChoices: [TimeInterval] {
        Self.choices([2, 5, 10, 15, 20, 30, 45, 60].map { $0 * 60 }.filter { $0 > pauseAfter }, with: saveAfter)
    }

    /// `values` with `current` among them, as when a test launches with a nudge or cap of seconds, so the picker
    /// shows it.
    private static func choices(_ values: [TimeInterval], with current: TimeInterval) -> [TimeInterval] {
        Set(values + [current]).sorted()
    }

    /// Whether the last session ended itself at the cap, which a banner explains until the next start (SES-4).
    var lastSessionReachedCap: Bool { lastSession.map { $0.id == cappedID } == true }

    /// Hides the cap banner, as its Edit was tapped.
    func dismissCapBanner() {
        cappedID = nil
    }

    var tagIDs: [Tag.ID] { session?.tagIDs ?? [] }

    /// Replaces the running session's tags (TAG-2).
    func setTags(_ ids: [Tag.ID]) {
        perform { try recorder.setTags(ids) }
    }

    /// Shows the stored session, after ending one that reached the cap and moving an ended one into
    /// history, or into the outbox if history can't save it (ADR 0007).
    ///
    /// Call when the app becomes active: the session may have changed in another process, such as
    /// a Live Activity, or have been restored after the app was killed.
    func refresh() {
        do {
            if let capped = try recorder.end(atCap: cap) {
                cappedID = capped.id
            }
            if let archived = try recorder.archive(to: history, or: outbox) {
                lastSession = archived
            }
            waitingCount = try outbox.sessions().count
        } catch {
            // Neither history nor the outbox could take it, so it stays stored and Start is refused.
            logger.error("Couldn't move the session out of the running-session file: \(error, privacy: .public)")
            isShowingStorageError = true
        }
        do {
            session = try recorder.current()
            if session != nil { isShowingWelcome = false }
        } catch {
            logger.error("Couldn't load the running session: \(error, privacy: .public)")
            isShowingStorageError = true
        }
        detector.sync(with: session)
        glance.show(
            session, cappedAt: timerSession == nil ? nil : cap, saveAfter: saveAfter, appOnScreen: isOnScreen)
        isPastNudge = timerSession?.whenPracticeReaches(nudge).map { $0 <= clock.now } ?? false
        // The notification waits for the running session to reach the nudge. A pause, a stop or a session already
        // past it cancels it, so it comes at most once per session.
        if notifiesStillPracticing, let session = timerSession, let date = session.whenPracticeReaches(nudge),
            date > clock.now
        {
            nudges.schedule(after: date.timeIntervalSince(clock.now), sessionID: session.id)
        } else {
            nudges.cancel()
        }
    }

    /// Runs `command`, then shows what is stored, moving a session it ended into history.
    ///
    /// A command the session rejects means another process changed it first. The refresh shows
    /// that change, so it isn't an error for the user.
    private func perform(_ command: () throws -> Void) {
        do {
            // A Pause or Stop after the cap, as from the Live Activity while the app sat suspended, ends the session
            // at the cap instead (SES-4): the refresh alone would keep the time past it, as a paused session is
            // never capped.
            if let capped = try recorder.end(atCap: cap) {
                cappedID = capped.id
            }
            try command()
        } catch is RecorderError, is SessionError {
            logger.info("Command superseded by another change to the session")
        } catch {
            logger.error("Couldn't store a session change: \(error, privacy: .public)")
            isShowingStorageError = true
        }
        refresh()
    }
}

/// What a notification opened Practice to show (SES-3). The daily reminder is about no session (SET-1).
struct NudgeOpening: Equatable {
    let sessionID: UUID?
    let pickingEnd: Bool
}

/// The battery's charge, from 0 to 1, and whether it's plugged in.
struct BatteryReading: Equatable {
    var level: Double
    var isPluggedIn: Bool
}

extension Date {
    /// This date's minute, at the seconds of `reference`, the session's other end (SES-3, SES-5). Time wheels
    /// show only minutes, so a picked time would otherwise keep hidden seconds, and a session picked as 2:00 to
    /// 3:00 could last 59:43. It stays in `range`, as the wheels do; a date already outside is left as it is,
    /// for the caller to reject.
    func keepingSeconds(of reference: Date, within range: ClosedRange<Date>) -> Date {
        guard range.contains(self) else { return self }
        let calendar = Calendar.autoupdatingCurrent
        func minute(of date: Date) -> Date { calendar.dateInterval(of: .minute, for: date)?.start ?? date }
        let picked = minute(of: self) + reference.timeIntervalSince(minute(of: reference))
        return min(max(picked, range.lowerBound), range.upperBound)
    }
}
