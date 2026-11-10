#if DEBUG
    import Foundation
    import PianismCore
    import PianismPersistence

    /// The App Store screenshots' sample practice (#56), with PIANISM_SHOWCASE=1 on a reset install: four weeks of
    /// evenings on four well-known pieces and two skills, mostly started by a piano, a session this morning, and a
    /// piano session 12 minutes 41 seconds in, plus a skill inside Scales that nothing is tagged with. Release builds
    /// leave it out. `testATappedDayShowsItsDate` scrolls it too, relying on sessions yesterday and today, and on
    /// enough below them to scroll at the largest text.
    enum Showcase {
        static func seed(into store: HistoryStore, running: any RunningSessionStore, clock: any WallClock) {
            let library = SwiftDataTagLibrary(store: store, clock: clock)
            let history = SwiftDataSessionHistory(store: store, clock: clock)
            let pieces = [
                ("Nocturne in E-flat, Op. 9 No. 2", "Frédéric Chopin"),
                ("Clair de lune", "Claude Debussy"),
                ("Prelude in C major, BWV 846", "Johann Sebastian Bach"),
                ("Gymnopédie No. 1", "Erik Satie"),
            ].compactMap { name, composer -> Tag.ID? in
                guard let piece = try? library.add(name: name, kind: .piece) else { return nil }
                try? library.setDetails(composer: composer, targetTempo: nil, id: piece.id)
                return piece.id
            }
            guard pieces.count == 4 else { return }
            // A skill inside a built-in one, so the deploy's two-device check has a tag with a parent to sync (TAG-5,
            // ADR 0013).
            _ = try? library.add(name: "D minor", kind: .skill, inside: BuiltInSkill.scales.rawValue)
            let skills = [BuiltInSkill.scales.rawValue, BuiltInSkill.sightReading.rawValue]
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: clock.now)
            let minutes = [32, 25, 41, 18, 36, 28, 45]
            // Most evenings, skipping one day in five, so the week shows a gap or two.
            for daysAgo in 1...27 where daysAgo % 5 != 4 {
                // By the calendar, so the evening the clocks go back still starts at 6 pm.
                guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today),
                    let start = calendar.date(bySettingHour: 18, minute: (daysAgo % 3) * 30, second: 0, of: day)
                else { continue }
                let length = TimeInterval(minutes[daysAgo % minutes.count] * 60)
                // A timer session every third day, so each piece has some of both.
                let byPiano = daysAgo % 3 != 0
                var session = PracticeSession(
                    startedAt: start, timeZone: calendar.timeZone, source: byPiano ? .midi : .timer)
                try? session.setTags([pieces[daysAgo % 4], skills[daysAgo % 2]])
                if byPiano {
                    try? session.pause(at: start + length / 2)
                    try? session.resume(at: start + length / 2 + 180)
                }
                try? session.stop(at: start + length + (byPiano ? 180 : 0))
                try? history.save(session)
            }
            var morning = PracticeSession(startedAt: today + 8 * 3_600, timeZone: calendar.timeZone, source: .midi)
            try? morning.setTags([pieces[2], skills[0]])
            try? morning.stop(at: today + 8 * 3_600 + 22 * 60)
            try? history.save(morning)
            var now = PracticeSession(startedAt: clock.now - 761, timeZone: calendar.timeZone, source: .midi)
            try? now.setTags([pieces[0]])
            try? now.noteLastPlayed(at: clock.now - 1)
            try? running.update { $0 = now }
        }
    }
#endif
