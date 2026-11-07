import Foundation
import PianismCore
import TelemetryDeck
import Testing

@testable import PianismAnalytics

/// Records what the SDK posts, in place of the network.
private final class FakeNetwork: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var bodies: [String] = []

    static var posted: [String] {
        lock.withLock { bodies }
    }

    static func reset() {
        lock.withLock { bodies = [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
        Self.lock.withLock { Self.bodies.append(String(decoding: body, as: UTF8.self)) }
        let url = request.url ?? URL(filePath: "/")
        if let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil) {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

/// One at a time, as the SDK is a single shared manager and the fake network is shared too. Every test ends with
/// analytics off, so a manager left behind by one can't post during the next.
@Suite(.serialized)
@MainActor
struct TelemetryDeckAnalyticsTests {
    private let analytics: TelemetryDeckAnalytics

    init() {
        FakeNetwork.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FakeNetwork.self]
        analytics = TelemetryDeckAnalytics(
            appID: "00000000-0000-0000-0000-000000000000", urlSession: URLSession(configuration: configuration),
            transmitInterval: 0.1)
    }

    private var posted: String { FakeNetwork.posted.joined() }

    private func waitForPost(of text: String) async throws {
        for _ in 0..<100 where !posted.contains(text) {
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Long enough for anything still on its way to have gone, at the short interval above, past the SDK's 0.5 s delay
    /// before a session starts.
    private func settle() async throws {
        try await Task.sleep(for: .seconds(1.5))
    }

    @Test func whileOnASignalReachesTheNetworkWithItsDetails() async throws {
        analytics.setEnabled(true)
        analytics.send(.sessionSaved(.midi))
        try await waitForPost(of: "Practice.sessionSaved")
        analytics.setEnabled(false)
        #expect(posted.contains("Practice.sessionSaved"))
        #expect(posted.contains(#""source":"midi""#))
    }

    /// The app opening is on the ADR's list.
    @Test func aSessionStartSignalIsSent() async throws {
        analytics.setEnabled(true)
        try await waitForPost(of: "TelemetryDeck.Session.started")
        analytics.setEnabled(false)
        #expect(posted.contains("TelemetryDeck.Session.started"))
    }

    /// The SDK's session statistics, which send a new-install signal, aren't. It remembers an install across test runs,
    /// so the setting is what can be checked.
    @Test func theSDKsSessionStatisticsAreOff() {
        #expect(!analytics.makeConfig().sessionStatsEnabled)
    }

    /// With the SDK not started at all, as when analytics is off at launch. Sending would trap here, in a Debug build.
    @Test func neverTurnedOnNothingGoesOut() async throws {
        try await settle()
        TelemetryDeck.terminate()
        analytics.send(.firstLaunch)
        try await settle()
        #expect(FakeNetwork.posted.isEmpty)
    }

    /// The network used while off answers without going anywhere. This address doesn't exist, so a real one would fail.
    @Test func whileOffTheNetworkGoesNowhere() async throws {
        let url = try #require(URL(string: "https://pianism.invalid/"))
        let (_, response) = try await DiscardingNetwork.session().data(from: url)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
    }

    /// The switch's promise: a signal still queued when analytics is turned off doesn't go, and it's gone for good.
    @Test func turningOffDiscardsWhatWasQueued() async throws {
        analytics.setEnabled(true)
        try await settle()
        analytics.send(.firstLaunch)
        analytics.setEnabled(false)
        try await settle()
        #expect(!posted.contains("Install.firstLaunch"))
        analytics.setEnabled(true)
        try await settle()
        analytics.setEnabled(false)
        #expect(!posted.contains("Install.firstLaunch"))
    }

    /// As when the app comes back from the background, which starts a new session.
    @Test func whileOffNothingFurtherGoesOut() async throws {
        analytics.setEnabled(true)
        try await settle()
        analytics.setEnabled(false)
        try await settle()
        FakeNetwork.reset()
        analytics.send(.activationReached)
        TelemetryDeck.generateNewSession()
        TelemetryDeck.signal("Anything")
        try await settle()
        #expect(FakeNetwork.posted.isEmpty)
    }

    /// Such as a new session when the app comes back: it isn't kept for when analytics is next on.
    @Test func whatHappensWhileOffStaysGoneOnceBackOn() async throws {
        analytics.setEnabled(true)
        try await settle()
        analytics.setEnabled(false)
        TelemetryDeck.signal("Anything")
        analytics.setEnabled(true)
        try await settle()
        analytics.setEnabled(false)
        #expect(!posted.contains("Anything"))
    }

    @Test func turningOnAgainSends() async throws {
        analytics.setEnabled(true)
        analytics.setEnabled(false)
        analytics.setEnabled(true)
        analytics.send(.activationReached)
        try await waitForPost(of: "Activation.reached")
        analytics.setEnabled(false)
        #expect(posted.contains("Activation.reached"))
    }
}
