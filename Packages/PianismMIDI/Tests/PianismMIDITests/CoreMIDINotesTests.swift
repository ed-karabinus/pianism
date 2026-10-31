import CoreMIDI
import Foundation
import PianismCoreTestSupport
import Testing

@testable import PianismMIDI

/// Played through virtual sources, which are software, so the tests need no piano. They never assume their sources
/// are the only ones: the stream holds only Note Ons, so a connected keyboard's Active Sensing doesn't reach it. The
/// time limit turns a note that never arrives into a failure rather than a stuck run. They run on the main actor, so
/// the first MIDI client is made on the main thread and CoreMIDI's announcements arrive, as in the app.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct CoreMIDINotesTests {
    let clock = ManualClock()

    @Test("MIDI-R1: only a Note On with a velocity counts, even where a longer message's word looks like one")
    func onlyNoteOnsWithVelocityReachTheStream() async throws {
        let piano = try VirtualSource()
        let midi = CoreMIDINotes(clock: clock)
        var notes = midi.notes.makeAsyncIterator()
        try await waitUntil { midi.sources.contains(piano.endpoint) }
        let start = clock.now

        piano.send([
            0x2080_3C40,  // Note Off
            0x20B0_407F,  // the sustain pedal
            0x2090_3C00,  // Note On with no velocity, which means Note Off
            0x3016_0102, 0x2090_3C40,  // SysEx, whose second word reads as a Note On on its own
            0x5090_3C40, 0, 0, 0,  // a mixed data set payload, whose first word has a Note On's status
            0x2090_3C40,  // Note On
        ])
        #expect(await notes.next() == start)
        clock.advance(by: 1)
        piano.send([0x2090_4040])
        #expect(await notes.next() == start + 1)
    }

    @Test("MIDI-R7: two pianos' notes merge into one stream")
    func twoSourcesMergeIntoOneStream() async throws {
        let (first, second) = (try VirtualSource(), try VirtualSource())
        let midi = CoreMIDINotes(clock: clock)
        var notes = midi.notes.makeAsyncIterator()
        try await waitUntil { midi.sources.isSuperset(of: [first.endpoint, second.endpoint]) }
        let start = clock.now

        first.send([0x2090_3C40])
        #expect(await notes.next() == start)
        clock.advance(by: 1)
        second.send([0x2090_4040])
        #expect(await notes.next() == start + 1)
    }

    @Test("MIDI-R6: a piano connected before launch is heard without being plugged in again")
    func aSourceThatExistedBeforeTheAdapterIsHeard() async throws {
        let piano = try VirtualSource()

        let midi = CoreMIDINotes(clock: clock)

        #expect(midi.sources.contains(piano.endpoint))
        var notes = midi.notes.makeAsyncIterator()
        piano.send([0x2090_3C40])
        #expect(await notes.next() == clock.now)
    }

    @Test("MIDI-R6: a piano plugged in after launch is heard")
    func aSourceThatAppearsAfterLaunchIsHeard() async throws {
        let midi = CoreMIDINotes(clock: clock)
        var notes = midi.notes.makeAsyncIterator()

        let piano = try VirtualSource()

        try await waitUntil { midi.sources.contains(piano.endpoint) }
        piano.send([0x2090_3C40])
        #expect(await notes.next() == clock.now)
    }

    @Test("MIDI-R6: unplugging one piano lets go of it and leaves the other heard")
    func aRemovedSourceStopsNothingElse() async throws {
        var first: VirtualSource? = try VirtualSource()
        let second = try VirtualSource()
        let midi = CoreMIDINotes(clock: clock)
        var notes = midi.notes.makeAsyncIterator()
        let unplugged = try #require(first?.endpoint)
        try await waitUntil { midi.sources.isSuperset(of: [unplugged, second.endpoint]) }

        first = nil

        try await waitUntil { !midi.sources.contains(unplugged) }
        second.send([0x2090_3C40])
        #expect(await notes.next() == clock.now)
    }

    @Test("MIDI-2: the pianos heard are named as they come and go")
    func connectedPianosAreNamed() async throws {
        let name = "Test piano \(UUID())"
        let midi = CoreMIDINotes(clock: clock)
        var pianos = midi.pianos.makeAsyncIterator()
        var names: [String]?

        do {
            let piano = try VirtualSource(named: name)
            repeat { names = await pianos.next() } while names?.contains(name) == false
            #expect(names?.contains(name) == true)
            withExtendedLifetime(piano) {}
        }

        repeat { names = await pianos.next() } while names?.contains(name) == true
        #expect(names?.contains(name) == false)
    }

    /// Waits up to 10 s for CoreMIDI to announce a change, which it does on the main run loop.
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition() {
            try #require(ContinuousClock.now < deadline, "CoreMIDI didn't announce the change")
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// A piano in software: a MIDI source that sends what a test gives it.
@MainActor
private final class VirtualSource {
    private var client = MIDIClientRef()
    private(set) var endpoint = MIDIEndpointRef()

    init(named name: String = "Test piano") throws {
        try #require(MIDIClientCreateWithBlock(name as CFString, &client, nil) == noErr)
        try #require(MIDISourceCreateWithProtocol(client, name as CFString, ._1_0, &endpoint) == noErr)
    }

    deinit {
        MIDIEndpointDispose(endpoint)
        MIDIClientDispose(client)
    }

    /// Sends these Universal MIDI Packet words as one packet.
    func send(_ words: [UInt32]) {
        var list = MIDIEventList()
        let packet = MIDIEventListInit(&list, ._1_0)
        _ = MIDIEventListAdd(&list, MemoryLayout<MIDIEventList>.size, packet, 0, words.count, words)
        MIDIReceivedEventList(endpoint, &list)
    }
}
