import CoreMIDI
import Foundation
import PianismCore
import Synchronization
import os

/// The keys struck on every connected piano (MIDI-R6), merged into one stream (MIDI-R7).
///
/// Only a Note On with a velocity counts (MIDI-R1): Note Off, the pedals and everything else are dropped here.
public final class CoreMIDINotes: Sendable {
    /// Each key struck, dated by the clock when it arrives (ADR 0009).
    public let notes: AsyncStream<Date>
    /// The names of the pianos it hears, as CoreMIDI gives them, each time they change (MIDI-2).
    public let pianos: AsyncStream<[String]>

    private let continuation: AsyncStream<Date>.Continuation
    private let pianosContinuation: AsyncStream<[String]>.Continuation
    private let clock: any WallClock
    private let midi = Mutex(Connection())
    private let logger = Logger(subsystem: "com.edkarabinus.Pianism", category: "midi")

    private struct Connection {
        var client = MIDIClientRef()
        var port = MIDIPortRef()
        var sources = Set<MIDIEndpointRef>()
        var names: [String] = []
    }

    /// Starts listening. If CoreMIDI won't let it, it logs why and the streams stay empty.
    ///
    /// CoreMIDI announces pianos coming and going on the run loop of the thread that made the process's first MIDI
    /// client, so this is made on the main thread, whose run loop runs for the app's lifetime.
    @MainActor
    public init(clock: any WallClock) {
        self.clock = clock
        (notes, continuation) = AsyncStream.makeStream()
        (pianos, pianosContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        // The blocks are @Sendable, so they aren't taken to run on the main actor: CoreMIDI calls each on a thread of
        // its own, and a block isolated to the main actor would stop the app there.
        var client = MIDIClientRef()
        var status = MIDIClientCreateWithBlock("Pianism" as CFString, &client) { @Sendable [weak self] notification in
            switch notification.pointee.messageID {
            case .msgObjectAdded, .msgObjectRemoved, .msgSetupChanged: self?.connectAll()
            default: break
            }
        }
        var port = MIDIPortRef()
        if status == noErr {
            midi.withLock { $0.client = client }  // so deinit disposes of it, even if the port fails
            status = MIDIInputPortCreateWithProtocol(client, "Notes" as CFString, ._1_0, &port) {
                @Sendable [weak self] list, _ in
                self?.receive(list)
            }
        }
        guard status == noErr else {
            logger.error("Can't listen for MIDI: OSStatus \(status)")
            return
        }
        midi.withLock { $0.port = port }
        connectAll()
    }

    deinit {
        continuation.finish()
        pianosContinuation.finish()
        midi.withLock { _ = MIDIClientDispose($0.client) }
    }

    /// The sources it hears now.
    // periphery:ignore - the adapter tests wait on it, and Periphery doesn't index package tests
    var sources: Set<MIDIEndpointRef> { midi.withLock { $0.sources } }

    /// Connects every source that's online and lets go of each that went, then says which pianos it hears if that
    /// changed. A piano unplugged and plugged back in may keep its endpoint while its old connection hears nothing, so
    /// it's connected again.
    private func connectAll() {
        midi.withLock { midi in
            let online = Set(
                (0..<MIDIGetNumberOfSources()).map(MIDIGetSource).filter { source in
                    var offline: Int32 = 0
                    MIDIObjectGetIntegerProperty(source, kMIDIPropertyOffline, &offline)
                    return offline == 0
                })
            for source in midi.sources.subtracting(online) {
                MIDIPortDisconnectSource(midi.port, source)
                midi.sources.remove(source)
            }
            for source in online.subtracting(midi.sources) where MIDIPortConnectSource(midi.port, source, nil) == noErr
            {
                midi.sources.insert(source)
            }
            let names = Set(midi.sources.map(Self.displayName(of:))).sorted()
            guard names != midi.names else { return }
            midi.names = names
            pianosContinuation.yield(names)
            logger.info("Pianos heard: \(names, privacy: .public)")
        }
    }

    /// The name the system shows for a source, such as "MIDI KEYBOARD" for a piano over USB.
    private static func displayName(of source: MIDIEndpointRef) -> String {
        var name: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &name)
        return name?.takeRetainedValue() as String? ?? ""
    }

    /// Yields a date for each Note On with a velocity. It steps through each packet by message size, so a word of a
    /// longer message, such as SysEx data, never reads as a Note On.
    private func receive(_ list: UnsafePointer<MIDIEventList>) {
        for packet in list.unsafeSequence() {
            let words = MIDIEventPacket.WordCollection(packet)
            var index = words.startIndex
            while index < words.endIndex {
                let word = words[index]
                // A MIDI 1.0 channel voice message: type 2, status 9 for Note On, velocity in the low 7 bits.
                if word >> 28 == 0x2, word >> 20 & 0xF == 0x9, word & 0x7F > 0 {
                    continuation.yield(clock.now)
                }
                index += Self.wordsPerMessage[Int(word >> 28)]
            }
        }
    }

    /// Each Universal MIDI Packet's size in 32-bit words, by message type.
    private static let wordsPerMessage = [1, 1, 1, 2, 2, 4, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4]
}
